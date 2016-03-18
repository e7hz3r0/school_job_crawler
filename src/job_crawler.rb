require 'spidr'
require 'yaml'

class JobCrawler
  job_regex = /(job|career|opportunities|employment)/i
  biology_teacher = /(living environment|biology|science)/i

  config = YAML.load(File.open(File.expand_path('../../config/config.yml', __FILE__)))

  urls = config['base_urls']

  urls.each do |url|
    Spidr.start_at(url) do |spider|
#      spider.every_failed_url {|fail| puts fail}
      spider.every_page do |page| 
        puts "Checking: #{page.title}"
        if page.title =~ job_regex && page.body =~ biology_teacher
          puts "POSSIBLE JOB FOUND"
          puts page.title
          puts page.url
        else 
          page.search('//a[@href]') do |a|
            puts a.inspect
          end
        #else
          #spider.skip_page!
        end
      end
    end
  end
end
