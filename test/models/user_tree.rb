require "mongoid"
require "mongoid_acts_as_tree"

# every user has his own tree
class UserTree
  include Mongoid::Document
  include Mongoid::Acts::Tree

  field :name, :type => String
  field :user_id, :type => Integer
  field :unlinkable, :type => Boolean, :default => true
  field :moveable, :type => Boolean, :default => true
  
  acts_as_tree :scope => :user_id  
  
  set_callback :move_absolute, :before, :custom_before_absolute_move
  set_callback :unlink, :before, :custom_before_unlink
  
  def custom_before_absolute_move
    return self.moveable
  end

  def custom_before_unlink
    return self.unlinkable
  end


end
