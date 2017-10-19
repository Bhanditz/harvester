json.total_pages @media.total_pages
json.current_page @media.current_page
json.media @media do |medium|
  # TODO: make sure name_verbatim and description_verbatim have at least been copied...
  json.extract! medium,
    *%i[guid resource_pk subclass format owner source_url name description unmodified_url
        source_page_url rights_statement usage_statement sizes location_id bibliographic_citation_id]

  json.page_id medium.node.page_id
  json.name medium.name_verbatim if medium.name.blank?
  json.description medium.description_verbatim if medium.description.blank?
  # TODO: this should be configurable.
  if Rails.env.development?
    json.base_url "http://localhost:3000#{medium.base_url}"
  else
    json.base_url "http://beta-repo.eol.org#{medium.base_url}"
  end
  json.license medium.license.try(:url)
  if medium.language
    json.language do
      json.extract! medium.language, :group_code, :code
    end
  end
end