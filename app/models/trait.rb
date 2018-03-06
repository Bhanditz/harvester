# An measurement formed by combining a 'measurment or fact' with an 'occurrence'.
class Trait < ActiveRecord::Base
  belongs_to :parent, inverse_of: :children, class_name: 'Trait', foreign_key: 'parent_id'
  belongs_to :resource, inverse_of: :traits
  belongs_to :harvest, inverse_of: :traits
  belongs_to :node, inverse_of: :traits
  belongs_to :object_node, class_name: 'Node', inverse_of: :traits
  belongs_to :predicate_term, class_name: 'Term'
  belongs_to :object_term, class_name: 'Term'
  belongs_to :units_term, class_name: 'Term'
  belongs_to :statistical_method_term, class_name: 'Term'
  belongs_to :sex_term, class_name: 'Term'
  belongs_to :lifestage_term, class_name: 'Term'
  belongs_to :occurrence, inverse_of: 'traits'

  has_many :meta_traits, inverse_of: :trait
  has_many :children, class_name: 'Trait', inverse_of: :parent, foreign_key: 'parent_id'
  has_many :traits_references, inverse_of: :trait
  has_many :references, through: :traits_references

  scope :published, -> { where(removed_by_harvest_id: nil) }
  scope :primary, -> { where(of_taxon: true) }
  scope :matched, -> { where('node_id IS NOT NULL') }
  scope :unmatched, -> { where('node_id IS NULL') }

  def metadata
    (meta_traits + references + children + occurrence.occurrence_metadata).compact
  end

  def eol_pk
    "R#{resource_id}-PK#{id}"
  end

  def page_id
    node.page_id
  end

  def scientific_name
    node.scientific_name.italicized
  end

  def predicate
    predicate_term.uri
  end

  def sex
    sex_term&.uri
  end

  def lifestage
    lifestage_term&.uri
  end

  def statistical_method
    statistical_method_term&.uri
  end

  def object_page_id
    nil
  end

  def target_scientific_name
    nil
  end

  def value_uri
    object_term&.uri
  end

  def units
    units_term&.uri
  end

  def convert_measurement
    return unless measurement
    num = measurement_to_num
    if num.is_a?(Numeric) && units_term && !units_term.uri.blank?
      (n_val, n_unit) = UnitConversions.convert(num, units_term.uri)
      update_attributes(normal_measurement: n_val, normal_units_uri: n_unit)
    elsif units_term && !units_term.uri.blank?
      update_attributes(normal_measurement: num, normal_units_uri: units_term.uri)
    else
      update_attributes(normal_measurement: num, normal_units_uri: '')
    end
    save
  end

  def measurement_to_num
    Integer(measurement)
  rescue ArgumentError, TypeError
    begin
      Float(measurement)
    rescue ArgumentError, TypeError
      measurement
    end
  end
end
