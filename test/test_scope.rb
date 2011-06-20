require 'helper'
require 'set'

$verbose = false

class TestMongoidActsAsTree < Test::Unit::TestCase
  context "TreeScope" do
    setup do
      @root_1     = UserTree.create(:name => "Root 1", :user_id => 1234)
      @child_1    = UserTree.new(:name => "Child 1", :user_id => 1234)
      @child_2    = UserTree.new(:name => "Child 2", :user_id => 1234)
      @child_2_1  = UserTree.new(:name => "Child 2.1", :user_id => 1234)

      @child_3    = UserTree.new(:name => "Child 3", :user_id => 1234)
      @root_2     = UserTree.create(:name => "Root 2", :user_id => 6789)

      @root_1.children << @child_1
      @root_1.children << @child_2
      @root_1.children << @child_3

      @child_2.children << @child_2_1
      
    end

   	should "should block scope missmatch" do
   	  child  = UserTree.new(:name => 'Child 4', :user_id => 1234);
   	  assert_raise Mongoid::Acts::Tree::ScopeError do
   		  @root_2.children << child
		  end
		end

  end
end

