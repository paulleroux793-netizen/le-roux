require 'rails_helper'

RSpec.describe 'Per-user authentication', type: :request do
  let!(:user) { User.create!(email: 'recep@test.com', password: 'secret123', name: 'Reception One', role: 'reception') }

  describe 'with USER_AUTH_ENABLED off (the live default)' do
    it 'leaves the dashboard open — current behaviour is unchanged' do
      get '/'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'with USER_AUTH_ENABLED on' do
    around do |ex|
      prev = ENV['USER_AUTH_ENABLED']
      ENV['USER_AUTH_ENABLED'] = 'true'
      ex.run
      ENV['USER_AUTH_ENABLED'] = prev
    end

    it 'redirects an unauthenticated request to the login page' do
      get '/'
      expect(response).to redirect_to(login_path)
    end

    it 'renders the login page' do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Login')
    end

    it 'rejects wrong credentials' do
      post login_path, params: { email: user.email, password: 'nope' }
      expect(response).to redirect_to(login_path)
    end

    it 'logs in with correct credentials and reaches the dashboard' do
      post login_path, params: { email: user.email, password: 'secret123' }
      expect(response).to redirect_to(root_path)
      get '/'
      expect(response).to have_http_status(:ok)
      expect(user.reload.last_login_at).to be_present
    end

    it 'logs out and re-locks the dashboard' do
      post login_path, params: { email: user.email, password: 'secret123' }
      delete logout_path
      expect(response).to redirect_to(login_path)
      get '/'
      expect(response).to redirect_to(login_path)
    end

    it 'refuses a deactivated user' do
      user.update!(active: false)
      post login_path, params: { email: user.email, password: 'secret123' }
      expect(response).to redirect_to(login_path)
    end
  end

  describe 'User model' do
    it 'authenticates the right password and rejects the wrong one' do
      expect(user.authenticate('secret123')).to be_truthy
      expect(user.authenticate('wrong')).to be_falsey
    end

    it 'downcases the email' do
      u = User.create!(email: 'MixedCase@Example.COM', password: 'secret123', name: 'X', role: 'admin')
      expect(u.email).to eq('mixedcase@example.com')
    end

    it 'exposes role predicates' do
      expect(user.reception?).to be(true)
      expect(user.admin?).to be(false)
    end

    it 'validates role inclusion' do
      expect(User.new(email: 'a@b.com', password: 'secret123', name: 'X', role: 'wizard')).not_to be_valid
    end
  end
end
