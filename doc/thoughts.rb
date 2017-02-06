# Skip ahead for the local code.

# From the website (i.e.: Not actually in this codebase, but I need to think
# about it):

# The website would periodically request harvests from the repository:
repository = RepositoryApi.new
per_page = 1000
deltas = {}
types = [:pages, :nodes, :scientific_names, :media, :etc]
actions = [:new, :changed, :removed]
# TODO: first we need to communicate which resources are available, so we get new resources,
resources = repository.diffs_since?(RepositorySync.last.created_at)
resources.each do |resource|
  repository.resource_diffs_since?(resource, RepositorySync.last.created_at).each do |diff|
    types.each do |type|
      actions.each do |action|
        next unless diff[type][action] &&
                    diff[type][action].to_i > 0
        page = 1
        have = 0
        while have < diff[type][action]
          response = repository.get_diff_deltas(resource_id: resource.id,
            since: RepositorySync.last.created_at, type: type, action: action,
            page: page, per_page: per_page)
          # TODO: error-handling
          deltas[type][action] += response[type]
          have += response.size
          page += 1
          last if response[:no_more_items]
        end
      end
    end
  end
  types.each do |type|
    actions.each do |action|
      # I didn't sketch out these actions. Some of them would be moderately
      # complex, since they need to denormalize things, and the :media type
      # would be broken up into subtypes, etc...
      call(:"bulk_#{action}", deltas[type][action])
    end
  end
end

# This implies a response structure to "diffs_since" a bit like this:
{
  pages: {
    new: 10,
    changed: 2,
    removed: 0 },
  nodes: {
    new: 27,
    changed: 0,
    removed: 0 },
  scientific_names: {
    new: 256,
    changed: 0,
    removed: 12 },
  media: {
    new: 103,
    changed: 12,
    removed: 6 },
  etc: "etc"
}

# And then a response structure to get_diff_deltas something like this, assuming
# the params were resource_id: 1, since: "2017-01-13 10:36:25", type: "nodes",
# action: "new" page: 1, per_page: 10
{
  nodes: [
    { "repository_id"=>603,
      "page_id"=>1115346,
      "rank"=>"species",
      "parent_repository_id"=>602,
      "scientific_name"=>"<i>Echinochloa crus-galli</i> (L.) P. Beauv.",
      "canonical_form"=>"<i>Echinochloa crus-galli</i>",
      "resource_pk"=>"9786302",
      "source_url"=>
        "http://www.catalogueoflife.org/annual-checklist/details/species/id/9786302" }
  ],
  no_more_items: "true"
}
# And for action: "removed"
{
  nodes: [
    { "resource_pk"=>"9786302" }
  ],
  no_more_items: "true"
}
# And for action "changed" ... note that this allows the SITE to do
# reconciliation with curations (which occurred on that site)
{
  nodes: [
    { "resource_pk"=>"9786302",
      "repository_id"=>927845,
      "source_url"=> "http://www.catalogueoflife.org/annual-checklist/species/id/9786302" }
  ],
  no_more_items: "true"
}

# WE ARE IGNORING CURATION FOR NOW. It will be a significant question about how
# we handle it: we could either let the sites manage their own curation, so
# everyone is an island, or we could send all curation back to the harvesting
# repository. Or something in between (say, ignoring curatorial edits, or
# ignoring everything except node curation, etc). Thoughts required.

#
# Name Matching
#

# What should be stored in a speedy index... I'm writing the queries in
# pseudo-SQL syntax for brevity/portability:
Index:
  Pages:
    scientific_name: (preferred by DWH)
    synonyms: (synonyms from DWH)
    other_synonyms: (from all sources)
    canonical_name: (from DWH)
    canonical_synonyms: (from DWH)
    other_canonical_synonyms: (from all sources)
    ancestor_ids: ordered (proximal to root)
    other_ancestor_ids: (from other hierarchies)
    child_ids: (from DWH) # ... I am not sure we want/need this in the index, but we'll need to get it, and be mindful of performance.
    is_hybrid: identified either expplicitly during import or by gnparser

# some variables which are assumed to be defined:
@resource = "the resource that has been harvested"
@harvest = "some record of the harvest event itself"
@index = "some kind of connection to the index"
root_nodes = "all of the nodes from the resource; stored as a nested "\
  "hierarchy; this variable references the root nodes, which we'll walk down"
# Method names, in the order in which they should be attempted:
@strategies: [
  { attribute: :scientific_name, index: :scientific_name, type: :eq },
  { attribute: :scientific_name, index: :synonyms, type: :in },
  { attribute: :scientific_name, index: :other_synonyms, type: :in },
  { attribute: :canonical_name, index: :canonical_name, type: :eq },
  { attribute: :canonical_name, index: :canonical_synonyms, type: :in },
  { attribute: :canonical_name, index: :other_canonical_synonyms, type: :in }
]
# Constants like these really should be CONFIGURABLE, not hard-coded, so we can
# change a text file on the server and re-run something to try new values.
@child_match_weight = 1 # We will want this for tweaking, over time...
@ancestor_match_weight = 1 # Ditto...
@max_ancestor_depth = 3 # We would like to be able to change this...

# The algorithm, as pseudo-code (Ruby, for brevity):
def map_all_nodes(root_nodes)
  @harvest.log_mapping_started
  map_nodes(root_nodes)
  @harvest.log_mapping_completed
end

def map_nodes(nodes)
  nodes.each do |node|
    map_if_needed(node)
  end
end

def map_if_needed(node)
  if node.needs_to_be_mapped?
    map_node(node, ancestor_depth: 0, strategy: 0)
  end
  map_nodes(node.children) if node.children.any?
end

def map_node(node, opts = {})
  # NOTE: Surrogates never get matched in this version of the algorithm.
  return unmapped(node) if node.is_surrogate?
  # NOTE: Node.native_virus returns the "Virus" node in the DWH. NOTE: If the
  # node has been flagged (by gnparser) as a virus, then it may ONLY match other
  # viruses.
  ancestor = if node.is_virus?
    Node.native_virus
  else
    # NOTE: #matched_ancestor walks up the node's ancestors and returns the Nth #
    # non-nil page, or nil if none.
    node.matched_ancestor(opts[:ancestor_depth])
  end
  q = build_search_query(node, ancestor, opts)
  results = @index.pages.where(q)
  if results.size == 1
    return node.map_to_page(results.first)
  elsif results.size > 1
    return more_than_one_match(node, results)
  else # no results found!
    # YOU WERE HERE ... choose the next strategy (including looping around with
    # a new ancestor depth if possible), try again, or use unmapped...
    # opts[:ancestor_depth] ||= 1
    # opts[:ancestor_depth] += 1
    # need to check max_ancestor_depth, of course.
  end
end

def more_than_one_match(node, matching_pages)
  scores = {}
  matching_pages.each do |matching_page|
    scores[matching_page] = {}
    # NOTE: #child_names will have to get the (let's go with canonical) names of
    # all the children. NOTE: #count_matches does exactly what it implies:
    # counts the number of (exactly the same) strings.
    scores[matching_page][:matching_children] =
      count_matches(matching_page.child_names, node.child_names)
    scores[matching_page][:matching_ancestors] =
      # NOTE: this is idiomatic ruby for "count the number of ancestors with
      # page_ids assigned":
      node.ancestor.select { |a| ! a.page_id.nil? }.size
    scores[matching_page][:score] =
      scores[matching_page][:matching_children] * @child_match_weight +
      scores[matching_page][:matching_ancestors] * @ancestor_match_weight
  end
  best_match = nil
  best_score = 0
  scores.each do |page, details|
    best_match = page if details[:score] > best_score
  end
  node.map_to_page(best_match)
  @harvest.log_multiple_matches(node, scores)
end

def build_search_query(node, ancestor, opts)
  strategy = @strategies[opts[:strategy]]
  q = strategy[:index]
  # TODO: in Solr I think this really just becomes ":" in BOTH cases...
  q += strategy[:type] == :in ? " IN " : " = "
  q += "'#{node.send(strategy[:attribute])}'" # TODO: proper quoting, of course.
  if ancestor
    q += if opts[:other_ancestors]
      " AND (other_ancestor_ids INCLUDES "\
        "#{ancestor.node_ids.join(" OR other_ancestor_ids INCLUDES ")})"
    else
      " AND ancestor_ids INCLUDES #{ancestor.native_node.id}"
    end
  end
  q += " AND is_hybrid = True" if node.is_hybrid?
end

def unmapped(node, options = {})
  node.create_new_page
  @harvest.log_unmapped_node(node)
end
