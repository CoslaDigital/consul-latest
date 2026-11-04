require "rails_helper"

RSpec.describe "Rack::Attack", type: :request do
  # Fake a public IP so we don't trigger the allow-internal-ips safelist.
  let(:headers) { { "REMOTE_ADDR" => "192.168.1.100" } }

  before(:each) do
    @previous_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  after(:each) do
    Rack::Attack.enabled = @previous_enabled
    Rack::Attack.cache.store.clear
  end

  describe "login-per-email throttle" do
    # Make the per-IP login limit effectively infinite so it can't mask the
    # per-email limit under test.
    before do
      allow(Rack::Attack).to receive(:login_ip_limit).and_return(1_000_000)
    end

    let(:email) { "student@school.edu" }

    it "allows 10 login attempts and blocks the 11th" do
      10.times do
        post "/ys_login", params: { email: email }, headers: headers
        expect(response.status).not_to eq(429)
      end

      post "/ys_login", params: { email: email }, headers: headers
      expect(response.status).to eq(429)
      expect(response.body).to include("Too many requests")
    end

    it "does not block a different email after the first is throttled" do
      11.times { post "/ys_login", params: { email: email }, headers: headers }
      expect(response.status).to eq(429)

      post "/ys_login", params: { email: "teacher@school.edu" }, headers: headers
      expect(response.status).not_to eq(429)
    end
  end

  describe "login-per-ip throttle" do
    before do
      allow(Rack::Attack).to receive(:login_ip_limit).and_return(5)
    end

    it "blocks the 6th attempt from the same IP regardless of email" do
      5.times do |i|
        post "/ys_login", params: { email: "user#{i}@school.edu" }, headers: headers
        expect(response.status).not_to eq(429)
      end

      post "/ys_login", params: { email: "user6@school.edu" }, headers: headers
      expect(response.status).to eq(429)
    end
  end
end
