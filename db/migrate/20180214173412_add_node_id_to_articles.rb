class AddNodeIdToArticles < ActiveRecord::Migration
  def change
    # Honestly, I can't imagine how I missed these. :/
    add_column :articles, :node_id, :integer
    add_column :articles, :node_resource_pk, :string
  end
end
