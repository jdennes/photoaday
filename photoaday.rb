require 'rubygems'
require 'yaml'
require 'haml'
require 'sinatra'
require 'date'

FlickRawOptions = if File.exists?('flickraw.yaml')
  YAML.load_file('flickraw.yaml')
else
  { 'api_key' => ENV['api_key'] }
end

require 'flickraw'

# Rather than installing activesupport gem, extend Fixnum
class Fixnum
  def ordinalize
    if (11..13).include?(self % 100)
      "#{self}th"
    else
      case self % 10
        when 1; "#{self}st"
        when 2; "#{self}nd"
        when 3; "#{self}rd"
        else    "#{self}th"
      end
    end
  end
end

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

  def current_photo_date_taken
    dt = DateTime.parse(flickr.photos.getInfo(:photo_id => current_photo['id']).dates['taken'])
    return dt.strftime("%A the #{dt.day.ordinalize} of %B, %Y")
  end

  def other_thumbnails
    matching_photos.to_a.collect do |photo|
      [photo.title, FlickRaw.url_t(photo), "/photo/#{photo['id']}"]
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
      :extra_info => 'date_taken,path_alias,url_sq,url_t,url_s,url_m,url_o'
    }
  end
  
  def format_date_taken(taken)
    return 
  end
end

get '/' do
  search = FlickrSearch.new
  @photo = search.current_photo
  raise not_found unless @photo
  
  @description = search.current_photo_description
  @date_taken = search.current_photo_date_taken
  @photo_url = FlickRaw.url(@photo)
  @photo_link = FlickRaw.url_photopage(@photo)
  @other_thumbnails = search.other_thumbnails
  haml :index
end

get '/photo/:photo_id' do
  search = FlickrSearch.new(params[:photo_id])
  @photo = search.current_photo
  raise not_found unless @photo

  @description = search.current_photo_description
  @date_taken = search.current_photo_date_taken
  @photo_url = FlickRaw.url(@photo)
  @photo_link = FlickRaw.url_photopage(@photo)
  @other_thumbnails = search.other_thumbnails

  haml :index
end

not_found do
  haml :not_found
end

error do
  haml :error
end