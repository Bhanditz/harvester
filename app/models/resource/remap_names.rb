class Resource
  class RemapNames
    def self.for_resource(resource)
      self.new(resource).match
    end

    def initialize(resource)
      @resource = resource
      @harvest = @resource.harvests.complete_non_failed.last
      @nodes_to_pages = []
    end

    def match
      @harvest.log('START: Remapping Names', cat: :starts)
      create_nodes_to_pages_map
      @harvest.nodes.update_all(page_id: nil, matching_log: nil)
      re_run_names_matcher
      create_publish_map
      File.unlink(nodes_to_pages_map_file) # ...it was mostly there for posterity.
      @harvest.log('END: Remapping Names', cat: :ends)
    end

    def create_nodes_to_pages_map
      @harvest.log_call
      @harvest.nodes.find_each do |node|
        @nodes_to_pages << [node.id, node.resource_pk, node.page_id, node.matching_log]
      end
      CSV.open(nodes_to_pages_map_file, 'wb') do |csv|
        @nodes_to_pages.each { |line| csv << line }
      end
    end

    def re_run_names_matcher
      @harvest.log_call
      NamesMatcher.for_harvest(@harvest)
      @harvest.update_attribute(:nodes_matched_at, Time.now)
    end

    def create_publish_map
      @harvest.log_call
      @nodes_to_pages = CSV.read(nodes_to_pages_map_file)
      publish_map = []

      @nodes_to_pages.in_groups_of(1000, false) do |lines|
        ids = lines.map(&:first)
        nodes = {}
        @harvest.nodes.where(id: ids).find_each do |node|
          nodes[node.id] = node.page_id
        end
        lines.each do |line|
          # NOTE: a line, here, is [node.id, node.resource_pk, node.page_id (the old one), node.matching_log]
          publish_map << [line[1], line[2], nodes[line[0].to_i]] # Thus: resource PK, old page, new page.
        end
      end

      CSV.open("#{@resource.path}/publish_nodes_remap.csv", 'wb') do |csv|
        publish_map.each { |line| csv << line }
      end
    end

    def nodes_to_pages_map_file
      "#{@resource.path}/nodes_to_pages.csv"
    end
  end
end
