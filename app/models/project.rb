class Project < ActiveRecord::Base
  attr_accessible :user_id, :title, :description, :lead_image 
  has_paper_trail on: [:create, :update]
  belongs_to :user
  has_many :medias
  has_many :project_sources
  has_many :sources , through: :project_sources
  mount_uploader :lead_image, ImageUploader
  validates_presence_of :title

  private
  
  def user_id_callback(value)
    user = User.where(name: value).last
    user.nil? ? nil : user.id
  end
end