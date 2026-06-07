require "sinatra"

set :public_folder, File.expand_path("public", __dir__)
set :host_authorization, { permitted_hosts: [] }
disable :protection
set :show_exceptions, false
set :raise_errors, false

get "/" do
  send_file File.join(settings.public_folder, "index.html")
end

get "/_health" do
  "ok"
end
