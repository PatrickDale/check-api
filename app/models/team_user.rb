class TeamUser < ActiveRecord::Base
  attr_accessible

  belongs_to :team
  belongs_to :user

  def user_id_callback(value, _mapping_ids = nil)
    user_callback(value)
  end

  def team_id_callback(value, mapping_ids = nil)
    mapping_ids[value]
  end

end
