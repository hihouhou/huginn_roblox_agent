require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::RobloxAgent do
  before(:each) do
    @valid_options = Agents::RobloxAgent.new.default_options
    @checker = Agents::RobloxAgent.new(:name => "RobloxAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
