# Sitemap.xml Generator is a Jekyll plugin that generates a sitemap.xml file by 
# traversing all of the available posts and pages.
# 
# See readme file for documenation
# 
# Updated to use config file for settings by Daniel Groves
# Site: http://danielgroves.net
# 
# Author: Michael Levin
# Site: http://www.kinnetica.com
# Distributed Under A Creative Commons License
#   - http://creativecommons.org/licenses/by/3.0/
require 'jekyll/document'
require 'rexml/document'

module Jekyll

    class Jekyll::Document
        attr_accessor :name

        def path_to_source
            File.join(*[@name].compact)
        end

        def location_on_server(my_url)
            "#{my_url}#{url}"
        end
    end

    class Page
        attr_accessor :name

        def path_to_source
            File.join(*[@dir, @name].compact)
        end

        def location_on_server(my_url)
            location = "#{my_url}#{url}"
            location.gsub(/index.html$/, "")
        end
    end

    # Recover from strange exception when starting server without --auto
    class SitemapFile < StaticFile
        def write(dest)
            true
        end
    end

    class SitemapGenerator < Generator
        priority :lowest

        # Front Matter parameters
        FRONT_MATTER_SITEMAP = "sitemap"
        
        # Config defaults
        SITEMAP_FILE_NAME = "/sitemap.xml"
        EXCLUDE = ["/atom.xml", "/feed.xml", "/feed/index.xml"]
        INCLUDE_POSTS = ["/index.html"] 
        CHANGE_FREQUENCY_NAME = "change_frequency"
        PRIORITY_NAME = "priority"
        LASTMOD_NAME = "lastmod"
        
        # Valid values allowed by sitemap.xml spec for change frequencies
        VALID_CHANGE_FREQUENCY_VALUES = ["always", "hourly", "daily", "weekly", "monthly", "yearly", "never"] 

        # Goes through pages and posts and generates sitemap.xml file
        #
        # Returns nothing
        def generate(site)
            # Configuration
            sitemap_config = site.config['sitemap'] || {}
            @config = {}
            @config['filename'] = sitemap_config['filename'] || SITEMAP_FILE_NAME
            # @config['change_frequency_name'] = sitemap_config['change_frequency_name'] || CHANGE_FREQUENCY_NAME
            # @config['priority_name'] = sitemap_config['priority_name'] || PRIORITY_NAME
            @config['exclude'] = sitemap_config['exclude'] || EXCLUDE
            @config['include_posts'] = sitemap_config['include_posts'] || INCLUDE_POSTS
            @config['lastmod_name'] = sitemap_config['lastmod_name'] || LASTMOD_NAME

            # Initialise the XML document
            sitemap = REXML::Document.new << REXML::XMLDecl.new("1.0", "UTF-8")

            # Create the main XML node
            urlset = REXML::Element.new "urlset"
            urlset.add_attribute("xmlns", "http://www.sitemaps.org/schemas/sitemap/0.9")
            urlset.add_attribute("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
            urlset.add_attribute("xsi:schemaLocation", "http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd")

            # Insert all posts and pages as children of the main XML node
            fill_posts(site, urlset)
            fill_pages(site, urlset)

            # Insert the XML node into the XML document
            sitemap.add_element(urlset)

            # Create destination directory if it doesn't exist yet. Otherwise, we cannot write our file there.
            Dir::mkdir(site.dest) if !File.directory? site.dest

            # Create sitemap.xml file and write out pretty-printed XML
            filename = @config['filename']
            file = File.new(File.join(site.dest, filename), "w")
            formatter = REXML::Formatters::Pretty.new(4)
            formatter.compact = true
            formatter.write(sitemap, file)
            file.close

            # Keep the sitemap.xml file from being cleaned by Jekyll
            site.static_files << Jekyll::SitemapFile.new(site, site.dest, "/", filename)
        end

        # Create url elements for all the posts
        #
        # Returns nothing
        def fill_posts(site, urlset)
            # Iterate through all posts
            site.collections["posts"].docs.each do |post|
                # Only process non-excluded posts
                if !excluded?(site, post.name)
                    url = fill_url_post(site, post)
                    urlset.add_element(url)
                end

                date = File.mtime(post.path)
                last_modified_date = date if last_modified_date == nil or date > last_modified_date
            end
        end

        # Create url elements for all the normal pages and find the date of the
        # index to use with the pagination pages
        #
        # Returns last_modified_date of index page
        def fill_pages(site, urlset)
            site.pages.each do |page|
                if !excluded?(site, page.path_to_source) and File.exists?(page.path)
                    url = fill_url_page(site, page)
                    urlset.add_element(url)
                end
            end
        end

        # Fill data of each URL element: location, last modified, change frequency (optional), and priority.
        # For posts only.
        #
        # Returns url REXML::Element
        def fill_url_post(site, post)
            # Create XML node "url"
            url = REXML::Element.new "url"
            # Get the "loc" node and add it to the "url" node
            loc = fill_location(site, post)
            url.add_element(loc)
            # Generate the lastmod value
            lastmod = REXML::Element.new "lastmod"
            if (post.data[@config['lastmod_name']])
                lastmod.text = post.data[@config['lastmod_name']].iso8601
            else
                lastmod.text = post.date.iso8601
            end
            url.add_element(lastmod) 

            # if (post.data[@config['change_frequency_name']])
            #     change_frequency = post.data[@config['change_frequency_name']].downcase
                
            #     if (valid_change_frequency?(change_frequency))
            #         changefreq = REXML::Element.new "changefreq"
            #         changefreq.text = change_frequency
            #         url.add_element(changefreq)
            #     else
            #         puts "ERROR: Invalid Change Frequency In #{post.name}"
            #     end
            # end

            # if (post.data[@config['priority_name']])
            #     priority_value = post.data[@config['priority_name']]
            #     if valid_priority?(priority_value)
            #         priority = REXML::Element.new "priority"
            #         priority.text = post.data[@config['priority_name']]
            #         url.add_element(priority)
            #     else
            #         puts "ERROR: Invalid Priority In #{post.name}"
            #     end
            # end

            url
        end

        # Fill data of each URL element: location, last modified, change frequency (optional), and priority.
        # For pages only.
        #
        # Returns url REXML::Element
        def fill_url_page(site, page)
            # Create XML node "url"
            url = REXML::Element.new "url"
            # Get the "loc" node and add it to the "url" node
            loc = fill_location(site, page)
            url.add_element(loc)
            # Generate the lastmod value
            lastmod = fill_last_modified_page(site, page)
            url.add_element(lastmod) if lastmod

            # if (page.data[@config['change_frequency_name']])
            #     change_frequency = page.data[@config['change_frequency_name']].downcase
                
            #     if (valid_change_frequency?(change_frequency))
            #         changefreq = REXML::Element.new "changefreq"
            #         changefreq.text = change_frequency
            #         url.add_element(changefreq)
            #     else
            #         puts "ERROR: Invalid Change Frequency In #{page.name}"
            #     end
            # end

            # if (page.data[@config['priority_name']])
            #     priority_value = page.data[@config['priority_name']]
            #     if valid_priority?(priority_value)
            #         priority = REXML::Element.new "priority"
            #         priority.text = page.data[@config['priority_name']]
            #         url.add_element(priority)
            #     else
            #         puts "ERROR: Invalid Priority In #{page.name}"
            #     end
            # end

            url
        end

        # Get URL location of page or post 
        #
        # Returns the location of the page or post
        def fill_location(site, page_or_post)
            loc = REXML::Element.new "loc"
            url = site.config['url'] + site.config['baseurl']
            loc.text = page_or_post.location_on_server(url)

            loc
        end

        # Fill lastmod XML element with the last modified date for the page.
        #
        # Returns lastmod REXML::Element or nil
        def fill_last_modified_page(site, page)
            # puts page.name
            # puts page.to_yaml
            lastmod = REXML::Element.new "lastmod"
            if (page.data[@config['lastmod_name']])
                lastmod.text = page.data[@config['lastmod_name']].iso8601
            else
                date = File.mtime(page.path)
                latest_date = find_latest_date(date, site, page)
                lastmod.text = latest_date.iso8601
            end

=begin             
            if posts_included?(site, page.path_to_source)
                # We want to take into account the last post date
                final_date = greater_date(latest_date, @last_modified_post_date)
                lastmod.text = final_date.iso8601
            else
                lastmod.text = latest_date.iso8601
            end
=end
            lastmod
        end

        # Go through the page/post and any implemented layouts and get the latest
        # modified date
        #
        # Returns formatted output of latest date of page/post and any used layouts
        def find_latest_date(latest_date, site, page_or_post)
            layouts = site.layouts
            layout = layouts[page_or_post.data["layout"]]
            while layout
                date = File.mtime(layout.path)
                latest_date = date if (date > latest_date)
                layout = layouts[layout.data["layout"]]
            end

            latest_date
        end

        # Which of the two dates is later
        #
        # Returns latest of two dates
        def greater_date(date1, date2)
            if (date1 >= date2) 
                date1
            else 
                date2 
            end
        end

        # Is the page or post listed as something we want to exclude?
        #
        # Returns boolean
        def excluded?(site, name)
            @config['exclude'].include? name
        end

        def posts_included?(site, name)
            @config['include_posts'].include? name
        end

        # Is the change frequency value provided valid according to the spec
        #
        # Returns boolean
        def valid_change_frequency?(change_frequency)
            VALID_CHANGE_FREQUENCY_VALUES.include? change_frequency
        end

        # Is the priority value provided valid according to the spec
        #
        # Returns boolean
        def valid_priority?(priority)
            begin
                priority_val = Float(priority)
                return true if priority_val >= 0.0 and priority_val <= 1.0
            rescue ArgumentError
            end

            false
        end
    end
end