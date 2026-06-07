require_relative "../app"

RSpec.describe Sinatra::Application do
  def app
    Sinatra::Application
  end

  describe "GET /_health" do
    it "returns 200 with body 'ok'" do
      get "/_health"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq("ok")
    end
  end

  describe "GET /" do
    it "returns 200 and serves index.html" do
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Hello from Sinatra")
    end
  end

  describe "GET /styles.css" do
    it "returns 200 with CSS content type" do
      get "/styles.css"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("text/css")
      expect(last_response.body.strip).not_to be_empty
    end
  end

  describe "GET /app.js" do
    it "returns 200 with JS content type" do
      get "/app.js"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("javascript")
      expect(last_response.body.strip).not_to be_empty
    end
  end

  describe "GET /does-not-exist" do
    it "returns 404" do
      get "/does-not-exist"
      expect(last_response.status).to eq(404)
    end
  end
end
