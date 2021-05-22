# Sitemap.xml Generator is a Jekyll plugin that generates a sitemap.xml file by 
# traversing all of the available posts and pages.
# 
# See README file for documenation
# 
# Author: Pedro Monjo
# Site: https://www.pedromonjo.com
#
# Forked from https://github.com/kinnetica/jekyll-plugins
# Author: Michael Levin
# Site: http://www.kinnetica.com
#
# Distributed Under A Creative Commons License
#   - http://creativecommons.org/licenses/by/3.0/
#
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
            # There seems to be some weird bug with category paths
            if site.config["category_path"] and path_to_source.start_with?(site.config["category_path"])
                location = "#{my_url}/#{path_to_source}"
            else
                location = "#{my_url}#{url}"
            end
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
        VALID_FREQUENCY_VALUES = [ "always", "hourly", "daily", "weekly", "monthly", "yearly", "never" ] 

        def load_config(site)
            sitemap_config = site.config['sitemap'] || {}
            sitemap_config['frequency'] = sitemap_config['frequency'] || {}
            sitemap_config['priority'] = sitemap_config['priority'] || {}
            @config = {}
            @config['filename'] = sitemap_config['filename'] || SITEMAP_FILE_NAME
            @config['exclude'] = sitemap_config['exclude'] || EXCLUDE
            @config['include_posts'] = sitemap_config['include_posts'] || INCLUDE_POSTS
            @config['lastmod_name'] = sitemap_config['lastmod_name'] || LASTMOD_NAME
            @config['frequency_posts'] = sitemap_config['frequency']['posts'] || nil
            @config['frequency_pages'] = sitemap_config['frequency']['pages'] || nil
            @config['frequency_index'] = sitemap_config['frequency']['index'] || nil
            @config['priority_posts'] = sitemap_config['priority']['posts'] || nil
            @config['priority_pages'] = sitemap_config['priority']['pages'] || nil
            @config['priority_index'] = sitemap_config['priority']['index'] || nil
            @config['change_frequency_name'] = sitemap_config['change_frequency_name'] || CHANGE_FREQUENCY_NAME
            @config['priority_name'] = sitemap_config['priority_name'] || PRIORITY_NAME
        end

        # Goes through pages and posts and generates sitemap.xml file
        #
        # Returns nothing
        def generate(site)
            # Configuration
            load_config(site)

            # Initialise the XML document
            sitemap = REXML::Document.new << REXML::XMLDecl.new("1.0", "UTF-8")

            # Create the main XML node
            urlset = REXML::Element.new "urlset"
            urlset.add_attribute("xmlns", "http://www.sitemaps.org/schemas/sitemap/0.9")
            urlset.add_attribute("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
            urlset.add_attribute("xsi:schemaLocation", "http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd")

            # Insert all posts and pages as children of the main XML node
            fill_posts(site, urlset)
            fill_pages_index(site, urlset)

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
                if !excluded?(post.data['title'])
                    url = fill_url_post(site, post)
                    urlset.add_element(url)
                end
            end
        end

        # Create url elements for all the normal pages and indexes
        #
        # Returns nothing
        def fill_pages_index(site, urlset)
            # Iterate through all pages
            site.pages.each do |page|
                if !excluded?(page.path_to_source) and File.exists?(page.path)
                    if posts_included?(page.path_to_source)
                        url = fill_url_index(site, page)
                    else
                        url = fill_url_page(site, page)
                    end
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
            lastmod = fill_last_modified_post(post)
            url.add_element(lastmod) if lastmod
            # Generate the changefreq value
            changefreq = fill_change_frequency(post,@config['frequency_posts'])
            url.add_element(changefreq) if changefreq
            # Generate the priority value
            priority = fill_priority(post,@config['priority_posts'])
            url.add_element(priority) if priority

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
            lastmod = fill_last_modified_page(page)
            url.add_element(lastmod) if lastmod
            # Generate the changefreq value
            changefreq = fill_change_frequency(page,@config['frequency_pages'])
            url.add_element(changefreq) if changefreq
            # Generate the priority value
            priority = fill_priority(page,@config['priority_pages'])
            url.add_element(priority) if priority

            url
        end

        # Fill data of each URL element: location, last modified, change frequency (optional), and priority.
        # For indexes only.
        #
        # Returns url REXML::Element
        def fill_url_index(site, index)
            # Create XML node "url"
            url = REXML::Element.new "url"
            # Get the "loc" node and add it to the "url" node
            loc = fill_location(site, index)
            url.add_element(loc)
            # Generate the lastmod value
            lastmod = fill_last_modified_index(site)
            url.add_element(lastmod) if lastmod
            # Generate the changefreq value
            changefreq = fill_change_frequency(index,@config['frequency_index'])
            url.add_element(changefreq) if changefreq
            # Generate the priority value
            priority = fill_priority(index,@config['priority_index'])
            url.add_element(priority) if priority

            url
        end

        # Get URL location
        #
        # Returns the location of the page or post
        def fill_location(site, doc)
            loc = REXML::Element.new "loc"
            url = site.config['url'] + site.config['baseurl']
            loc.text = doc.location_on_server(url)

            loc
        end

        # Fill lastmod XML element with the last modified date for the post.
        # Updates object property @latest_post_date
        #
        # Returns lastmod REXML::Element or nil
        def fill_last_modified_post(post)
            lastmod = REXML::Element.new "lastmod"
            if (post.data[@config['lastmod_name']])
                date = post.data[@config['lastmod_name']]
            else
                date = post.date
            end
            lastmod.text = date.iso8601
            @latest_post_date = date if @latest_post_date == nil or date > @latest_post_date

            lastmod
        end

        # Fill lastmod XML element with the last modified date for the page.
        #
        # Returns lastmod REXML::Element or nil
        def fill_last_modified_page(page)
            lastmod = REXML::Element.new "lastmod"
            if (page.data[@config['lastmod_name']])
                lastmod.text = page.data[@config['lastmod_name']].iso8601
            else
                date = File.mtime(page.path)
                lastmod.text = date.iso8601
            end

            lastmod
        end

        # Fill lastmod XML element with the last modified date for the index.
        #
        # Returns lastmod REXML::Element or nil
        def fill_last_modified_index(index)
            lastmod = nil
            if (index.data[@config['lastmod_name']])
                lastmod = REXML::Element.new "lastmod"
                lastmod.text = index.data[@config['lastmod_name']].iso8601
            elsif @latest_post_date != nil
                lastmod = REXML::Element.new "lastmod"
                lastmod.text = @latest_post_date.iso8601
            end

            lastmod
        end

        # Fill changefreq XML element from the config or the document.
        #
        # Returns lastmod REXML::Element or nil
        def fill_change_frequency(doc, default_freq)
            changefreq = nil
            if doc.data[@config['change_frequency_name']]
                change_frequency = doc.data[@config['change_frequency_name']].downcase
                if (valid_change_frequency?(change_frequency))
                    changefreq = REXML::Element.new "changefreq"
                    changefreq.text = change_frequency
                else
                    puts "ERROR: Invalid change frequency in #{doc.name}: #{change_frequency}"
                end
            elsif (default_freq)
                change_frequency = default_freq
                if (valid_change_frequency?(change_frequency))
                    changefreq = REXML::Element.new "changefreq"
                    changefreq.text = change_frequency
                else
                    puts "ERROR: Invalid change frequency in configuration: #{change_frequency}"
                end
            end

            changefreq
        end

        # Fill priority XML element from the config or the document.
        #
        # Returns lastmod REXML::Element or nil
        def fill_priority(doc, default_prio)
            priority = nil
            if doc.data[@config['priority_name']]
                input_priority = doc.data[@config['priority_name']]
                if (valid_priority?(input_priority))
                    priority = REXML::Element.new "priority"
                    priority.text = input_priority
                else
                    puts "ERROR: Invalid priority in #{doc.name}: #{input_priority}"
                end
            elsif (default_prio)
                input_priority = default_prio
                if (valid_priority?(input_priority))
                    priority = REXML::Element.new "priority"
                    priority.text = input_priority
                else
                    puts "ERROR: Invalid change frequency in configuration: #{input_priority}"
                end
            end

            priority
        end

        # Is the page or post listed as something we want to exclude?
        #
        # Returns boolean
        def excluded?(name)
            @config['exclude'].each do |pattern|
                return true if File.fnmatch(pattern,name)
            end

            false
        end

        def posts_included?(name)
            @config['include_posts'].each do |pattern|
                return true if File.fnmatch(pattern,name)
            end

            false
        end

        # Is the change frequency value provided valid according to the spec
        #
        # Returns boolean
        def valid_change_frequency?(change_frequency)
            VALID_FREQUENCY_VALUES.include? change_frequency
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