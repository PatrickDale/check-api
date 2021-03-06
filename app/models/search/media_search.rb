class MediaSearch

  include CheckElasticSearchModel

  attribute :team_id, String
  attribute :project_id, String
  attribute :annotated_type, String
  attribute :annotated_id, String
  attribute :status, String
  attribute :title, String, mapping: { analyzer: 'hashtag' }
  attribute :description, String, mapping: { analyzer: 'hashtag' }
  attribute :quote, String, mapping: { analyzer: 'hashtag' }
  attribute :last_activity_at, Time, default: lambda { |_o, _a| Time.now.utc }

  before_save :set_last_activity_at

  def set_es_annotated(obj)
    self.send("annotated_type=", obj.class.name)
    self.send("annotated_id=", obj.id)
  end

  private

  def set_last_activity_at
    self.last_activity_at = Time.now.utc
  end

end
