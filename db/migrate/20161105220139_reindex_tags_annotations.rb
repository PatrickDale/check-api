class ReindexTagsAnnotations < ActiveRecord::Migration
  def change
    #repository = Elasticsearch::Persistence::Repository.new url: 'http://<es_host>:<es_port>', log: true
    repository = Elasticsearch::Persistence::Repository.new url: 'http://localhost:9200', log: true
    repository.index = 'temp_index'
    repository.document_type = Annotation.document_type
    Annotation.all_sorted.each{ |a| repository.save(a) }
    # delete current index
    Annotation.delete_index
    # restore from temp_index to original one
    Tag.create_index!
    # should get data using temp_index
    repository.search( query: {match_all: {}}).response['hits']['hits'][0]['_source'].each{ |tem_a| Annotation.save(tem_a) }
  end
end
