# Read a meta.xml config file and create the resource file formats.
class MetaConfig
  attr_accessor :resource, :path, :doc

  def self.import(path, resource = nil)
    new(path, resource).import
  end

  # NOTE: this doesn't *quite* seem to work, and I'm not sure why yet... Oh! It's because I'm not selecting the right
  # format. Ooops.
  def self.analyze
    hashes = {}
    Resource.find_each do |resource|
      format = resource.formats.last
      filename = format.get_from
      basename = File.basename(filename)
      filename = filename.sub(basename, 'meta.xml')
      unless File.exist?(filename)
        # puts "SKIPPING missing meta file for format: #{format.id}"
        next
      end
      @doc = File.open(filename) { |f| Nokogiri::XML(f) }
      tables = @doc.css('archive table')
      tables.each do |table|
        location = table.css("files location").first.text
        puts "++ #{resource.name}/#{location}"
        table.css('field').each do |field|
          i = field['index'].to_i
          format = resource.formats.where("get_from LIKE '%#{location}'")&.first
          if format.nil?
            # puts "SKIPPING missing format for #{location}"
            next
          end
          db_field = format.fields[i]
          if db_field.nil?
            # puts "SKIPPING missing db field for format #{format.id}..."
            next
          end
          key = "#{field['term']}/#{format.represents}"
          if hashes.key? key
            if hashes[key][:represents] == "to_ignored"
              # puts ".. It was ignored; overriding..."
            elsif hashes[key][:represents] == db_field.mapping
              next
            else
              puts "!! I'm leaving the old value for #{key} of #{hashes[key][:represents]} and losing the value "\
                "of #{db_field.mapping}"
              next
            end
          end
          hashes[key] = {
            term: field['term'],
            for_format: format.represents,
            represents: db_field.mapping,
            submapping: db_field.unique_in_format,
            is_unique: db_field.unique_in_format,
            is_required: !db_field.can_be_empty
          }
        end
      end
    end
    File.open(Rails.root.join('db', 'data', 'meta_analyzed.json'),"w") do |f|
      f.write(hashes.values.sort_by { |h| h[:term] }.to_json.gsub(/,/, ",\n"))
    end
    puts "Done. Created #{hashes.keys.size} hashes."
  end

  def initialize(path, resource = nil)
    @path = path
    @resource = resource || Resource.create
  end

  def import
    filename = "#{@path}/meta.xml"
    return 'Missing meta.xml file' unless File.exist?(filename)
    @doc = File.open(filename) { |f| Nokogiri::XML(f) }
    debugger
    tables = @doc.css('archive table')
    formats = []
    tables.each do |table|
      table_name = table.css("files location").text
      # TODO: :attributions, :articles, :images, :js_maps, :links, :maps, :sounds, :videos
      reps =
        case table['rowType']
        when "http://rs.tdwg.org/dwc/terms/Taxon"
          :nodes
        when "http://rs.tdwg.org/dwc/terms/Occurrence"
          :occurrences
        when "http://rs.tdwg.org/dwc/terms/MeasurementOrFact"
          :measurements
        when "http://eol.org/schema/reference/Reference"
          :refs
        when "http://eol.org/schema/agent/Agent"
          :agents
        when "http://eol.org/schema/media/Document"
          :media
        when "http://rs.gbif.org/terms/1.0/VernacularName"
          :vernaculars
        when "http://eol.org/schema/Association"
          :assocs
        end
      reps ||=
        case table_name.downcase
        when /^agent/
          :agents
        when /^tax/
          :nodes
        when /^ref/
          :refs
        when /^med/
          :media
        when /^(vern|common)/
          :vernaculars
        when /occurr/
          :occurrences
        when /assoc/
          :assocs
        when /(measurement|data|fact)/
          :measurements
        else
          raise "I cannot determine what #{table_name} represents!"
        end
      fmt = Format.create!(
        resource_id: @resource.id,
        harvest_id: nil,
        header_lines: table['ignoreHeaderLines'],
        data_begins_on_line: table['ignoreHeaderLines'],
        file_type: :csv,
        represents: reps,
        get_from: "#{@path}/#{table_name}",
        field_sep: table['fieldsTerminatedBy'],
        line_sep: table['linesTerminatedBy'],
        utf8: table['encoding'] =~ /^UTF/
      )
      fields = []
      table.css('field').each do |field|

      end
    end
  end
end