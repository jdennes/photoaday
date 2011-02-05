require 'yaml'
require 'haml'
require 'builder'
require 'sinatra'
require 'date'
require 'ostruct'

FlickRawOptions = if File.exists?('flickraw.yaml')
  YAML.load_file('flickraw.yaml')
else
  { 'api_key' => ENV['api_key'], 'shared_secret' => ENV['shared_secret'], 'auth_token' => ENV['auth_token'] }
end
require 'flickraw'

# BG_IMAGES = YAML.load_file('images.yaml') unless defined?(BG_IMAGES)

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

  def other_thumbnails
    matching_photos.to_a.collect do |photo|
      if photo.instance_of?(OpenStruct)
        [photo.title, photo.src, photo.href]
      else
        dt = DateTime.parse(photo['datetaken'])
        by = photo['ownername'].split()[0]
        taken = dt.strftime("%d %b, %Y by #{by}")
        ["#{photo.title} - #{taken}", FlickRaw.url_s(photo), "/photo/#{photo['id']}"]
      end
    end
  end

  protected

  def insert_missing_days(sorted_photos)
    # Find days on which a photo hasn't been taken and insert "forgotten" entries
    first_day = DateTime.parse(sorted_photos.last.datetaken)
    last_day = DateTime.now #parse(sorted_photos.first.datetaken)

    hashed = {}
    sorted_photos.each do |p|
      hashed["#{p.datetaken.split()[0]}|#{p.ownername.split()[0]}"] = p
    end

    first_day.upto(last_day) do |d|
      ["James", "Hadassah"].each do |n|
        if !hashed["#{d.strftime("%Y-%m-%d")}|#{n}"]
          f = OpenStruct.new({
            :datetaken => d.strftime("%Y-%m-%d %H:%M:%S"),
            :title => "Photo missing for #{d.strftime("%d %b, %Y")} by #{n}!",
            :src => "/question.png",
            :href => "/" })
          sorted_photos << f
        end
      end
    end
    sorted_photos.sort { |a,b| b.datetaken <=> a.datetaken }
  end

  def matching_photos
    if not @sorted
      james = flickr.photosets.getPhotos(search_conditions('72157625078364543'))
      dass = flickr.photosets.getPhotos(search_conditions('72157625203331992'))
      @sorted = (james['photo'].to_a | dass['photo'].to_a).sort { |a,b| b.datetaken <=> a.datetaken }
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

def get_bg
  # BG_IMAGES[rand(BG_IMAGES.size)]
  "http://farm3.static.flickr.com/2708/4503161659_0c6772d5f6_o.jpg"
end

def show_missing(params)
  return (params.has_key?("showmissing") and params["showmissing"] == "true")
end

get '/' do
  @bg = get_bg
  fc = FlickrClient.new(nil, show_missing(params))
  @photo = fc.current_photo
  if @photo  
    @description = fc.current_photo_description
    @date_taken = fc.current_photo_date_taken
    @photo_url = FlickRaw.url(@photo)
    @photo_link = FlickRaw.url_photopage(@photo)
    @other_thumbnails = fc.other_thumbnails
  end
  haml :index
end

get '/photo/:photo_id' do
  @bg = get_bg
  fc = FlickrClient.new(params[:photo_id], show_missing(params))
  @photo = fc.current_photo
  raise not_found unless @photo

  @description = fc.current_photo_description
  @date_taken = fc.current_photo_date_taken
  @photo_url = FlickRaw.url(@photo)
  @photo_link = FlickRaw.url_photopage(@photo)
  @other_thumbnails = fc.other_thumbnails

  haml :index
end

get '/feed' do
  fc = FlickrClient.new
  @other_thumbnails = fc.other_thumbnails
  builder do |xml|
    xml.instruct! :xml, :version => '1.0'
    xml.rss :version => "2.0" do
      xml.channel do
        xml.title "one photo every day"
        xml.description "This little thing is constructed by dass and james taking one photo each, every day."
        xml.link "http://photoaday.jdenn.es/"
        @other_thumbnails.each do |title, img_src_s, img_src_m, photo_url, taken|
          xml.item do
            url = "http://photoaday.jdenn.es#{photo_url}"
            xml.title title
            xml.link url
            xml.description title
            xml.pubDate Time.parse(taken.to_s).rfc822()
            xml.guid url
          end
        end
      end
    end
  end
end

not_found do
  haml :not_found
end

error do
  haml :error
end