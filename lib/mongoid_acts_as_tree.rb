require "mongoid"

module Mongoid
  module Acts
    module Tree
      def self.included(model)
        model.class_eval do
          extend InitializerMethods
        end
      end

      module InitializerMethods
        def acts_as_tree(options = {})
          options = {
            :parent_id_field => "parent_id",
            :path_field      => "path",
            :depth_field     => "depth",
            :autosave       => true
          }.merge(options)

          # set order to depth_field as default
          unless options[:order].present?
            options[:order] = options[:depth_field]
          end
          
          # setting scope if present
          if options[:scope].is_a?(Symbol) && options[:scope].to_s !~ /_id$/
            options[:scope] = "#{options[:scope]}_id".intern
          end

          write_inheritable_attribute :acts_as_tree_options, options
          class_inheritable_reader :acts_as_tree_options

          extend Fields
          extend ClassMethods

          # build a relation
          belongs_to  :parent, :class_name => self.base_class.to_s, :foreign_key => parent_id_field
          
          include InstanceMethods
          include Fields

          field path_field, :type => Array,  :default => [], :index => true
          field depth_field, :type => Integer, :default => 0                         
          
          self.class_eval do
            
            # overwrite parent_id_field=
            define_method "#{parent_id_field}=" do | new_parent_id |
              self.parent = new_parent_id.present? ? self.base_class.find(new_parent_id) : nil           
            end
            
            # overwrite parent=
            def parent_with_checking=(new_parent)
              if new_parent.present?
                if new_parent != self.parent && new_parent.is_a?(Mongoid::Acts::Tree)
                  self.write_attribute parent_id_field, new_parent.id
                  new_parent.children.push self, false
                end
              else
                self.write_attribute parent_id_field, nil
                self.path = []
                self.depth = 0
              end
              # chain to original relation
              parent_without_checking=(new_parent)
            end
            
            # use advise-around pattern to intercept mongoid relation
            alias_method_chain  'parent=', :checking
          end          
          
          before_destroy  :destroy_descendants
          
          define_callbacks  :move, :terminator => "result==false"
          define_callbacks  :unlink, :terminator => "result==false"  
            
        end
      end

      module ClassMethods
        
        
        def roots
          self.where(parent_id_field => nil).order_by tree_order
        end
        
        def base_class
          _base_class(self)
        end
        
        protected
        
        def _base_class(klass)
          # return if super class is object or does not include Mongoid::Acts::Tree
          if klass.superclass == Object || !klass.include?(Mongoid::Acts::Tree)
            klass
          else
            _base_class(klass.superclass)
          end
        end
        
        
      end

      module InstanceMethods        
        def [](field_name)
          self.send field_name
        end

        def []=(field_name, value)
          self.send "#{field_name}=", value
        end

        def ==(other)
          return true if other.equal?(self)
          return true if other.instance_of?(self.class) and other._id == self._id
          false
        end

        def root?
          self.parent_id.nil?
        end

        def root
          self.root? ? self : self.base_class.find(self.path.first)
        end

        def ancestors
          return [] if root? 
          self.base_class.where(:_id.in => self.path).order_by tree_order
        end

        def self_and_ancestors
          return [self] if root?
          self.base_class.where(:_id.in => [self._id] + self.path).order_by tree_order
        end

        def siblings
          # no siblings if new record and parent_id is nil! 
          # otherwise the other roots would be returned
          return [] if (new_record? && self.parent_id.nil?)
          self.base_class.where(:_id.ne => self._id, parent_id_field => self.parent_id).order_by tree_order
        end

        def self_and_siblings
          return [self] if (new_record? && self.parent_id.nil?)
          self.base_class.where(parent_id_field => self.parent_id).order_by tree_order 
        end

        def children
          Children.new self
        end

        def children=(new_children_list)
          self.children.clear
          new_children_list.each do | child |
            self.children << child
          end
        end

        alias replace children=

        def descendants
          return [] if new_record?
          self.base_class.all_in(path_field => [self._id]).order_by tree_order
        end

        def self_and_descendants
          return [self] if new_record?
          # new query to ensure tree order
          self.base_class.where({
            "$or" => [
                { path_field  => {"$all" => [self._id]}},
                { :_id        => self._id}
              ]
          }).order_by tree_order
        end

        def is_ancestor_of?(other)
          other.path.include?(self._id)
        end

        def is_or_is_ancestor_of?(other)
          (other == self) or is_ancestor_of?(other)
        end

        def is_descendant_of?(other)
          self.path.include?(other._id)
        end

        def is_or_is_descendant_of?(other)
          (other == self) or is_descendant_of?(other)
        end

        def is_sibling_of?(other)
          (other != self) and (other.parent_id == self.parent_id)
        end

        def is_or_is_sibling_of?(other)
          (other == self) or is_sibling_of?(other)
        end

        def destroy_descendants
          self.descendants.each &:destroy
        end
        
        def same_scope?(other)
          Array(tree_scope).all? do |attr|
            self.send(attr) == other.send(attr)
          end
        end        
        
        def base_class
          self.class.base_class
        end
        
        
        # setter and getters 
        
        def depth
          read_attribute depth_field
        end
        
        def depth=(new_depth)
          write_attribute depth_field, new_depth
        end
        
        def path
          read_attribute path_field
        end
        
        def parent_id
          read_attribute parent_id_field
        end
        
        # be careful with this one!
        def path=(new_path)
          write_attribute path_field, new_path
        end
          
      end

      #proxy class
      class Children < Array
        #TODO: improve accessors to options to eliminate object[object.parent_id_field]

        def initialize(owner)
          @parent = owner
          self.concat find_children_for_owner.to_a
        end

        #Add new child to list of object children
        def <<(object, will_save=true)
          if !object.is_a?(Mongoid::Acts::Tree)
            raise NonTreeError, 'Child is not a kind of Mongoid::Acts::Tree'
          elsif !@parent.persisted?
            raise UnsavedParentError, 'Cannot append child to unsaved parent'
          elsif object.base_class != @parent.base_class
            # child and parent must share same base class
            raise BaseClassError, 'Parent and child must share same base class'
          elsif !object.new_record? && object.descendants.include?(@parent)
            # if record is new, it can't have any children (=> UnsavedParent)
            raise CyclicError, 'Cyclic Tree Structure'
          elsif !@parent.same_scope?(object)
            # child and parent must be within the same scope
            raise ScopeError, 'Child must be in the same scope as parent'    
          else
            
            prev_depth  = object.depth
                        
            object.run_callbacks :move do
              
              object.write_attribute object.parent_id_field, @parent._id
              object.path = @parent.path + [@parent._id]
              object.depth = @parent.depth + 1
              # only will_save == false will block autosave
              object.save if will_save != false && object.tree_autosave 
            
              delta_depth  = object.depth - prev_depth
            
              # get self and all descendants ordered by ascending depth
              # temporary change tree_order
              # TODO: Prevent changing tree order because it cause unexpected behaviour
              prev_order = object.tree_order
              object.acts_as_tree_options[:order]  = [object.depth_field, :asc]
                
              # will not have any children if new record (unsaved parent)
              unless object.new_record?              
                object.descendants.each do |c_desc|
                  c_desc.run_callbacks :move do
                    # we need to adapt depth
                    c_desc.depth  = c_desc.depth + delta_depth
                    c_desc.path   = c_desc.path.slice(prev_depth, c_desc.path.length - prev_depth).unshift(*object.path)
                    # only will_save == false will block autosave
                    c_desc.save if will_save != false && object.tree_autosave 
                  end
                end
              end
              
              # restore old order
              object.acts_as_tree_options[:order] = prev_order
              
              super(object)
            end           
          end
        end

        def build(attributes, template_class=nil)
          # use same type as parent
          template_class = @parent.class if template_class.nil?
          
          if !template_class.include?(Mongoid::Acts::Tree)
            raise template_class.to_s + ' does not include Mongoid::Acts::Tree'
          end
          
          if !(template_class.base_class == @parent.base_class)
            raise template_class.to_s + ' does not share the same base class as parent'
          end
                    
          child = template_class.new(attributes)
          
          self.push child
          child
        end

        alias create build

        alias push <<

        #Deletes object only from children list.
        #To delete object use <tt>object.destroy</tt>.
        def delete(object_or_id)
          object = case object_or_id
            when String, BSON::ObjectId
              @parent.base_class.find object_or_id
            else
              object_or_id
          end

          object.run_callbacks :unlink do 
            object.parent = nil
            object.save

            super(object)
          end
        end

        #Clear children list
        def clear
          self.each do | child |
            @parent.children.delete child
          end
        end

        private

        def find_children_for_owner
          @parent.base_class.where(@parent.parent_id_field => @parent.id).
            order_by @parent.tree_order
        end
          
      end

      module Fields
        def parent_id_field
          acts_as_tree_options[:parent_id_field]
        end

        def path_field
          acts_as_tree_options[:path_field]
        end

        def depth_field
          acts_as_tree_options[:depth_field]
        end

        def tree_order
          acts_as_tree_options[:order] or []
        end
        
        def tree_scope
          acts_as_tree_options[:scope] or nil
        end        
        
        def tree_autosave
          acts_as_tree_options[:autosave]
        end
        
      end
      
      class TreeError < StandardError;end
      
      class CyclicError < TreeError;end
      
      class BaseClassError < TreeError;end
      
      class NonTreeError < TreeError; end 
      
      class ScopeError < TreeError;end
      
      class UnsavedParentError < TreeError;end
      
    end
  end
end

