# A web crawler in Ruby
#
# This script provides a generic Spider class for crawling urls and
# recording data scraped from websites. The Spider is to be used in
# collaboration with a "processor" class that defines which pages to
# visit and how data from those pages should be consumed. In this example
# the processor is ProgrammableWeb.
#
# Usage:
#   spider = ProgrammableWeb.new
#   spider.results.take(10)
#   => [{...}, {...}, ...]
#
# Requirements:
#   Ruby 2.0+
#
require "mechanize"
require "pry"
require 'nokogiri'
require 'logger'

class Spider
  REQUEST_INTERVAL = 1
  MAX_URLS = 1000

  attr_reader :handlers

  def initialize(processor, options = {}, logger = nil)
    @processor = processor

    @results  = []
    @urls     = []
    @handlers = {}

    @logger = logger 

    @interval = options.fetch(:interval, REQUEST_INTERVAL)
    @max_urls = options.fetch(:max_urls, MAX_URLS)

    enqueue(@processor.root, @processor.handler)
  end

  def enqueue(url, method, data = {})
    return if @handlers[url]
    @urls << url
    @handlers[url] ||= { method: method, data: data }
  end

  def record(data = {})
    @results << data
  end

  def results
    return enum_for(:results) unless block_given?

    i = @results.length
    enqueued_urls.each do |url, handler|
      begin
        @logger.info("Handling #{url.inspect}")
        @processor.send(handler[:method], agent.get(url), handler[:data])
        if block_given? && @results.length > i
          yield @results.last
          i += 1
        end
      rescue Net::HTTPResponse => ex
        if ex.response_code == '404'
          log 'Error', "Page not found: #{url.inspect}"
        else
          log "Error", "#{url.inspect}, #{ex}"
        end

      rescue => ex
        log "Error", "#{url.inspect}, #{ex}"
      end
      sleep @interval if @interval > 0
    end
  end

  private

  def enqueued_urls
    Enumerator.new do |y|
      index = 0
      while index < @urls.count && index <= @max_urls
        url = @urls[index]
        index += 1
        next unless url
        y.yield url, @handlers[url]
      end
    end
  end

  def log(label, info)
    warn "%-10s: %s" % [label, info]
  end

  def agent
    @agent ||= Mechanize.new
  end
end

class ProgrammableWeb
  JOB_REGEX = /(job|career|opportunities|employment)/i
  BIOLOGY_TEACHER = /(living environment|biology|science)/i

  attr_reader :root, :handler

  def initialize(root: [], handler: :process_index, **options)
    @root = root.shift
    @handler = handler
    @options = options
    @logger = Logger.new('job_crawler.log')
    @jobs = {}
    root.each do |site|
      spider.enqueue(site, :process_index)
    end
  end

  def process_index(page, data = {})
    found = page.body.scan(BIOLOGY_TEACHER)
    unless found.empty?
      @logger.info("Possible job at #{page.uri.to_s}. Matched: #{found}")
      doc = Nokogiri::HTML(page.body)
      spider.record({page.uri.to_s => [page.title.strip, found.flatten]})
      els = doc.search("//*[matches(text(),'#{BIOLOGY_TEACHER.source}')]", CustomFilter.new)
      jobs[page.uri.to_s] = els
    else 
      page.links_with(text: JOB_REGEX).each do |link|
        #puts "Found a job-related link, enqueuing '#{link.text}' - '#{link.href}'"
        spider.enqueue(link.href, :process_index)
      end
    end
#    page.links_with(href: %r{/api/\w+$}).each do |link|
#      spider.enqueue(link.href, :process_api, name: link.text)
#    end
  end


#  def process_api(page, data = {})
#    categories = page.search("article.node-api .tags").first.text.strip.split(/\s+/)
#    fields = page.search("#tabs-content .field").each_with_object({}) do |tag, results|
#      key = tag.search("label").text.strip.downcase.gsub(/[^\w]+/, ' ').gsub(/\s+/, "_").to_sym
#      val = tag.search("span").text
#      results[key] = val
#    end
#
#    spider.record data.merge(fields).merge(categories: categories)
#  end

  def results(&block)
    spider.results(&block)
  end

  def jobs
    return @jobs
  end

  private

  def spider
    @spider ||= Spider.new(self, @options, @logger)
  end
end

class CustomFilter
  def matches node_set, re
    node_set.find_all{|node| node.to_s =~ /#{re}/i}
  end
end

if __FILE__ == $0
  config = YAML.load(File.open(File.expand_path('../../config/config.yml', __FILE__)))
  urls = config['base_urls']

  spider = ProgrammableWeb.new(root: urls)

  spider.results.lazy.take(5).each_with_index do |result, i|
    warn "%-2s: %s" % [i, result.inspect]
  end
end
