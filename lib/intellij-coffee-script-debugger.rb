require 'intellij-coffee-script-debugger/version'
require 'intellij-coffee-script-debugger/source_map_comment'
require 'sprockets'
require 'sprockets/processing'
require 'sprockets/server'
require 'intellij-coffee-script-debugger/intellij_coffee_script'

module Sprockets
  class IntellijCoffeeScriptDebuggerClass < ::Rails::Railtie
    initializer "intellij.coffee.script.debugger", :after => "sprockets.environment" do |app|
      app.assets.register_postprocessor 'application/javascript', SourceMapComment
    end
  end

  module Server
    alias_method :old_call, :call

    def call(env)
      path = unescape(env['PATH_INFO'].to_s.sub(/^\//, ''))
      # URLs containing a `".."` are rejected for security reasons.
      if forbidden_request?(path)
        return forbidden_response
      end

      if File.extname(path) == '.coffee'
        asset = find_asset(path, :bundle => !body_only?(env), :source => true)

        if_stale(env, asset) do |headers|
          coffee_file = File.read(asset.pathname)
          [200, { 'Content-Type' => 'application/javascript' }.merge(headers), [coffee_file]]
        end
      elsif File.extname(path) == '.map'
        path = path.chomp('.map')
        asset = find_asset(path, :bundle => !body_only?(env))

        if File.extname(asset.pathname) != '.coffee'
          return old_call(env)
        end

        if_stale(env, asset) do |headers|
          coffee_file = File.read(asset.pathname)
          source_map_result = CoffeeScript.compile(coffee_file, {:format => :map, :filename => File.basename(asset.pathname)})
          source_map = source_map_result["v3SourceMap"]
          [200, { 'Content-Type' => 'application/json' }.merge(headers), [source_map]]
        end
      else
        old_call(env)
      end
    end

    def if_stale(env, asset)
      mtime = File.mtime asset.pathname
      modified_since = Time.parse(env["HTTP_IF_MODIFIED_SINCE"]) if env["HTTP_IF_MODIFIED_SINCE"]

      if modified_since and modified_since >= mtime
        [304, {}, []]
      else
        headers = { "Cache-Control" => "public", "Last-Modified" => mtime.httpdate }
        yield headers
      end
    end
  end
end
