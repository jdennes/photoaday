require 'yaml'
require 'haml'
require 'sinatra'
require 'date'
require 'ostruct'

FlickRawOptions = if File.exists?('flickraw.yaml')
  YAML.load_file('flickraw.yaml')
else
  { 'api_key' => ENV['api_key'], 'shared_secret' => ENV['shared_secret'], 'auth_token' => ENV['auth_token'] }
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

class FlickrClient
  def initialize(photo_id = nil, show_missing = false)
    @photo_id = photo_id
    @show_missing = show_missing
  end

  def current_photo
    @current_photo ||= if @photo_id
      matching_photos.to_a.find do |photo|
        !photo.instance_of?(OpenStruct) ? photo['id'] == @photo_id : false
      end
    else
      matching_photos.to_a.find do |photo|
        !photo.instance_of?(OpenStruct)
      end
    end
  end

  def current_photo_description
    flickr.photos.getInfo(:photo_id => current_photo['id']).description
  end

  def current_photo_date_taken
    dt = DateTime.parse(current_photo.datetaken)
    return dt.strftime("%A the #{dt.day.ordinalize} of %B, %Y by #{current_photo.ownername}")
  end

  def all_photos
    matching_photos.to_a.collect do |photo|
      if photo.instance_of?(OpenStruct)
        [photo.title, photo.src, photo.href]
      else
        dt = DateTime.parse(photo['datetaken'])
        by = photo['ownername'].split()[0]
        taken = dt.strftime("%a %d %b, %Y by #{by}")
        ["#{photo.title} - #{taken}", FlickRaw.url_s(photo), FlickRaw.url(photo), "/photo/#{photo['id']}", dt]
      end
    end
  end

  protected

  def insert_missing_days(sorted_photos)
    # Find days for which a photo isn't found and insert "missing" entries
    first_day = DateTime.parse(sorted_photos.last.datetaken)
    last_day = DateTime.now

    hashed = {}
    sorted_photos.each do |p|
      hashed["#{p.datetaken.split()[0]}"] = p
    end

    first_day.upto(last_day) do |d|
      if !hashed["#{d.strftime("%Y-%m-%d")}"]
        f = OpenStruct.new({
          :datetaken => d.strftime("%Y-%m-%d %H:%M:%S"),
          :title => "Photo missing for #{d.strftime("%d %b, %Y")}!",
          :src => "/question.png",
          :href => "/" })
        sorted_photos << f
      end
    end
    sorted_photos.sort { |a,b| b.datetaken <=> a.datetaken }
  end

  def matching_photos
    if not @sorted
      james = flickr.photosets.getPhotos(search_conditions('72157625078364543'))
      @sorted = (james['photo'].to_a).sort { |a,b| b.datetaken <=> a.datetaken }
      if @show_missing
        @sorted = insert_missing_days(@sorted)
      end
    end
    return @sorted
  end

  def search_conditions(photoset_id)
    { :photoset_id => photoset_id, :sort => 'date-taken-desc',
      :extras => 'date_taken,owner_name,path_alias,url_sq,url_t,url_s,url_m,url_o' }
  end
end

def show_missing(params)
  return (params.has_key?("showmissing") and params["showmissing"] == "true")
end

helpers do
  def partial(name, locals={})
    haml "_#{name}".to_sym, :layout => false, :locals => locals
  end
end

get '/' do
  fc = FlickrClient.new(nil, show_missing(params))
  @photo = fc.current_photo
  if @photo
    @description = fc.current_photo_description
    @date_taken = fc.current_photo_date_taken
    @photo_url = FlickRaw.url(@photo)
    @photo_link = FlickRaw.url_photopage(@photo)
    @thumbs = fc.all_photos
    @photo_count = @thumbs.length
  end
  haml :index
end

get '/photo/:photo_id/?' do
  fc = FlickrClient.new(params[:photo_id], show_missing(params))
  @photo = fc.current_photo
  raise not_found unless @photo

  @description = fc.current_photo_description
  @date_taken = fc.current_photo_date_taken
  @photo_url = FlickRaw.url(@photo)
  @photo_link = FlickRaw.url_photopage(@photo)
  @thumbs = fc.all_photos
  @photo_count = @thumbs.length
  haml :index
end

get '/feed/?' do
  content_type 'application/atom+xml', :charset => 'utf-8'
  fc = FlickrClient.new
  @photos = fc.all_photos
  haml :feed, {:format => :xhtml, :layout => false, :cache => false}
end

not_found do
  haml :not_found
end

error do
  haml :error
end