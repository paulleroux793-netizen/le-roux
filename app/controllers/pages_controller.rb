class PagesController < ApplicationController
  def dashboard
    render inertia: 'Dashboard'
  end
end
