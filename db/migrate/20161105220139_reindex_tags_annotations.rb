class ReindexTagsAnnotations < ActiveRecord::Migration
  def change
    repository = Elasticsearch::Persistence::Repository.new url: "http://#{CONFIG['elasticsearch_host']}:#{CONFIG['elasticsearch_port']}", log: true
    repository.index = 'temp_index'
    repository.document_type = Annotation.document_type
    # create a new mapping for tag into a temp index
    Tag.index_name = 'temp_index'
    Tag.create_index!
    Annotation.all_sorted.each{ |a| repository.save(a) }
    # delete current index
    Annotation.delete_index
    # restore from temp_index to original one
    # should get data using temp_index
    repository.search( query: {match_all: {}}).response['hits']['hits'][0]['_source'].each{ |tem_a| Annotation.save(tem_a) }
  end
end
