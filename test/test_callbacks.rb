require 'helper'
require 'set'

$verbose = false

class TestMongoidActsAsTree < Test::Unit::TestCase
  context "TreeCallbacks" do
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

   	should "should block unlink" do
   	  @child_1.unlinkable = false
   	  before = @root_1.children.size
   	  @root_1.children.delete(@child_1);
   	  
   	  assert @child_1.parent == @root_1
   	  assert @root_1.children.size == before   	  
   	  @child_1.unlinkable = true
		end
		
		should "should block move" do
		  @child_1.moveable = false
		  @child_2.children << @child_1
		
		  assert @child_1.parent == @root_1
		  @child_1.moveable = true
		end
  end
end

