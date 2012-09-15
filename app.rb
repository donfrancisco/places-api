require 'rubygems'
require 'bundler'

Bundler.require
$: << settings.root

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/config_file'
require 'active_support/json'
require 'active_support/core_ext/hash'

config_file 'config.yml'

class Places
  include HTTParty

  base_uri 'https://maps.googleapis.com/maps/api/place'
  headers('User-Agent' => 'Places-API, v0.1')

  def self.key=(key)
    default_params :key => key
  end

  def self.search(query, options = {})
    options.reverse_merge!(
      :input  => query,
      :sensor => false,
      :types  => 'geocode'
    )

    if country = options[:country]
      options[:components] = "country:#{country}"
    end

    result = get('/autocomplete/json', :query => options)

    places = (result['predictions'] || [])
    places.map {|place| details(place['reference']) }
  end

  def self.details(ref, options = {})
    query  = {reference: ref, sensor: false}.merge(options[:query] || {})
    result = get('/details/json', :query => query)
    self.new(result['result'])
  end

  attr_reader :name, :address, :phone, :lat, :lng,
              :street_number, :street_name, :neighborhood,
              :city, :state, :country, :zip

  def initialize(result)
    @result = Hashie::Mash.new(result)

    @name    = @result.name
    @address = @result.formatted_address
    @phone   = @result.formatted_phone_number
    @lat     = @result.geometry.location.lat
    @lng     = @result.geometry.location.lng

    # Oh, Google's & their APIs
    types = @result.address_components.inject({}) do |hash, comp|
      comp.types.each do |type|
        hash[type.to_sym] = comp.long_name
      end

      hash
    end

    @street_number = types[:street_number]
    @street_name   = types[:route]
    @neighborhood  = types[:neighborhood]
    @city          = types[:locality]
    @state         = types[:administrative_area_level_1]
    @country       = types[:country]
    @zip           = types[:postal_code]
  end

  def as_json(options = {})
    {
      :address => address,
      :line_1  => "#{street_number} #{street_name}",
      :line_2  => neighborhood,
      :city    => city,
      :state   => state,
      :zip     => zip
    }
  end
end

Places.key = settings.api_key

before do
  headers 'Access-Control-Allow-Origin' => settings.origin
end

get '/search', :provides => 'application/json' do
  if !params[:query] || params[:query].empty?
    halt 406
  end

  places = Places.search(
    params[:query],
    :country => params[:country]
  )
  places.to_json
end