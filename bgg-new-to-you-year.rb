#!/usr/bin/env ruby

# This is a modified version of Wes Baker's New-To-You script, which was designed to 
# list new games for a particular month and output a skeleton geeklist post with 
# ratings.
# 
# The modified script merely lists the new games a user has logged in a given calendar year
# and provides a count of those games.  This is to keep track of challenges like 51-in-15
# 

require 'date'
require 'optparse'
require 'open-uri'
require 'nokogiri'
require './game'

class NewToYouYear
  def initialize
    todays_date = Date.today
    @options = {
      :username     => 'mortenjohs',
      :year         => todays_date.year,
#      :year         => todays_date.year - 1,
    }

    parse_options

    ## start at beginning of year given
    @options[:start_date] = Date.parse(@options[:year].to_s + "-01-01")

    ## end at today, or at dec 31st of the given year if it is not in the current year
    if (@options[:start_date].year != Date.today.year)
      @options[:end_date] = Date.parse(@options[:year].to_s + "-12-31")
    else
      @options[:end_date] = todays_date
    end

    print_games(retrieve_plays())
  end

  # Parse out command line options
  def parse_options
    OptionParser.new do |opts|
      opts.banner = "Retrieve a listing of games that were new to you.
    Usage: bgg-new-to-you-year.rb --username UserName --year 2015"

      opts.on('-u username', '--username username', "Username") do |username|
        @options[:username] = username.to_s
      end

      opts.on('-y YEAR', '--year YEAR', 'Year (four digits, e.g. 2015)') do |year|
        @options[:year] = year.to_i
      end
    end.parse!
  end

  def retrieve_plays(start_date = @options[:start_date], end_date = @options[:end_date], username = @options[:username])
    # Retrieve games played in year
    page_num = 0
    num_results = 201;
    _games = Hash.new

    # until we get a page of results that is not full
    until num_results < 201 do
      #get the next page of results
      page_num += 1    

      plays = BGG_API.new('plays', {
        :username => username,
        :mindate  => start_date,
        :maxdate  => end_date,
  # not sure if this is necessary
        :subtype  => 'boardgame',
        :page     => page_num,
      }).retrieve

      #puts "PAGE " + page_num.to_s + " | COUNT = " + plays.root.children.count.to_s
      num_results = plays.root.children.count

      # First, get this year's plays
      plays.css('plays > play').each do |play|
        quantity = play.attr('quantity')
        item = play.search('item')
        name = item.attr('name').content
        objectid = item.attr('objectid').content.to_i

        # Create the hashes if need be
        unless _games.has_key? objectid
          _games[objectid] = Game.new
          _games[objectid][:objectid] = objectid
          _games[objectid][:name] = name
        end

        # Increment play count
        _games[objectid][:plays] = _games[objectid][:plays] + quantity.to_i
      end
    end

    puts "TOTAL PAGES FOR YEAR GIVEN: " + page_num.to_s


    #make one request for grabbing all games played before given year
    #we can only get 100 plays at a time, so we do this in multiple pages
    page_num = 0
    num_results = 201;

    # until we get a page of results that is not full
    until num_results < 201 do
      page_num += 1
      previous_plays = BGG_API.new('plays', {
          :username => username,
          # maybe this should be start_date minus 1 day?
          :maxdate => start_date, 
          :subtype => 'boardgame',
          :page    => page_num,
        }).retrieve
    
      #puts "PAGE " + page_num.to_s + " | COUNT = " + previous_plays.root.children.count.to_s
      num_results = previous_plays.root.children.count

      _games.each do |objectid, data|
        # filter out previously played games
        if previous_plays.xpath("//item[@objectid='" + objectid.to_s + "']").any? 
          #puts "deleting game " + _games[objectid][:name].to_s
          _games.delete(objectid)
        end        
      end
    end

    puts "TOTAL PAGES FOR PREVIOUS PLAYS: " + page_num.to_s
    return _games
  end

  def print_games(_games)
    # sort games by title (name)
    _games = _games.sort_by { |objectid, data| data[:name] }
    puts "=== New Games Played by " + @options[:username].to_s + " in " + @options[:year].to_s + " ==="
    # Print each game's name
    _games.each do |objectid, data|
      puts data[:objectid].to_s + " " + data[:name]
    end
    # print total number of new games this year
    puts "=== " + _games.length.to_s + " new games in " + @options[:year].to_s + " ==="
  end

  public :initialize
  private :parse_options, :retrieve_plays
end

# BGG API class that pulls in data and takes a hash as a set of options for the
# query string
class BGG_API
  @@bgg_api_url = "https://boardgamegeek.com/xmlapi2"

  def initialize(type, options)
    @type = type
    @options = options
  end

  def set_options(options)
    @options = @options.merge(options)
  end

  def retrieve
    query = "#{@@bgg_api_url}/#{@type}?"

    @options.each do |name, value|
      query << "#{name}=#{value}&"
    end

    # Remove the last ampersand
    query = query[0..-2]

    # Make sure we're receving a 200 result, otherwise wait and try again
    request = open(query)
    while (request.status[0] != "200")
      sleep 2
      request = open(query)
    end

    Nokogiri::XML(request.read)
  end
end

NewToYouYear.new
