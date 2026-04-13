require 'rails_helper'

RSpec.describe 'Pages', type: :request do
  describe 'GET /' do
    it 'returns 200' do
      get '/'
      expect(response).to have_http_status(:ok)
    end

    it 'renders the inertia page data' do
      get '/'
      expect(response.body).to include('data-page="app"')
      expect(response.body).to include('"component":"Dashboard"')
    end

    it 'includes vite tags and app element' do
      get '/'
      expect(response.body).to include('vite')
      expect(response.body).to include('<div id="app"></div>')
    end
  end
end
