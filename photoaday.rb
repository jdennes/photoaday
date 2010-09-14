require 'rubygems'
require 'yaml'
require 'haml'
require 'sinatra'

FlickRawOptions = YAML.load_file('flickraw.yaml')

require 'flickraw'

class FlickrSearch
  def initialize(photo_id = nil)
    @photo_id = photo_id
  end

  def current_photo
    @current_photo ||= if @photo_id
      matching_photos.to_a.find { |photo| photo['id'] == @photo_id }
    else
      matching_photos[0]
    end
  end
  
  def current_photo_description
    flickr.photos.getInfo(:photo_id => current_photo['id']).description
  end
  
  def other_thumbnails
    matching_photos.to_a.reverse.collect do |photo|
      [photo.title, FlickRaw.url_t(photo), "/show/#{photo['id']}"]
    end
  end
  
protected
  def matching_photos
    @matching_photos ||= flickr.photos.search(search_conditions)
  end
  
  def search_conditions
    {
      :user_id => '99761031@N00',
      :tags => 'hipstamatic',
      :sort => 'date-taken-desc',
      :per_page => 500,
      :extra_info => 'path_alias,url_sq,url_t,url_s,url_m,url_o'
    }
  end
end

get '/' do
  search = FlickrSearch.new
  @photo = search.current_photo
  etag(@photo['id'])
  @description = search.current_photo_description
  @photo_url = FlickRaw.url(@photo)
  @photo_link = FlickRaw.url_photopage(@photo)

  @other_thumbnails = search.other_thumbnails
  haml :index
end
