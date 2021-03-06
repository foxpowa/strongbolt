require 'spec_helper'

describe Strongbolt::Tenantable do
  it 'should have been included in ActiveRecord::Base' do
    expect(ActiveRecord::Base.included_modules).to include Strongbolt::Tenantable
  end

  #
  # When a class is set as tenant
  #
  describe 'tenant?' do
    context 'when class is not a tenant' do
      before do
        define_model 'OtherModel'
      end

      it 'should return false' do
        expect(OtherModel.tenant?).to eq false
      end
    end

    context 'when class is a tenant' do
      before do
        define_model 'OtherModel' do
          send :tenant
        end
      end
      after { Strongbolt.send :tenants=, [] }

      it 'should return true' do
        expect(OtherModel.tenant?).to eq true
      end
    end
  end

  #
  # Tenant setup
  #
  describe 'tenant setup' do
    #
    # When every association is properly configured
    #
    context 'when no configuration error' do
      #
      # Set up a series of models to test the tenant setup
      #
      before(:all) do
        #
        # Tenant Model
        #
        define_model 'TenantModel' do
          self.table_name = 'models'
          has_many :child_models, class_name: 'ChildModel'

          belongs_to :parent, class_name: 'UnownedModel',
                              foreign_key: :parent_id
        end

        #
        # Direct child to Tenant Model
        #
        define_model 'ChildModel' do
          self.table_name = 'child_models'

          belongs_to :tenant_model, foreign_key: :model_id,
                                    class_name: 'TenantModel'

          has_many :other_child_models, class_name: 'OtherChildModel'
          has_one :very_polymorphic_sibling_model, as: :model, class_name: 'VeryPolymorphicSiblingModel'
        end

        #
        # 2nd degree child of tenant model
        #
        define_model 'OtherChildModel' do
          self.table_name = 'child_models'

          belongs_to :child_model, foreign_key: :model_id,
                                   class_name: 'ChildModel'
          belongs_to :uncle_model, foreign_key: :parent_id,
                                   class_name: 'UncleModel'
          has_one :sibling_model, class_name: 'SiblingModel'
          has_one :polymorphic_sibling_model, class_name: 'PolymorphicSiblingModel'


          has_and_belongs_to_many :bottom_models,
                                  join_table: 'model_models',
                                  class_name: 'BottomModel',
                                  foreign_key: :parent_id,
                                  association_foreign_key: :child_id
        end

        #
        # Parent of second degree child
        #
        define_model 'UncleModel' do
          self.table_name = 'models'

          has_many :other_child_models, class_name: 'OtherChildModel'
          belongs_to :parent, class_name: 'UnownedModel',
                              foreign_key: :parent_id
        end

        #
        # Cousin of second degree child
        #
        define_model 'SiblingModel' do
          self.table_name = 'child_models'

          belongs_to :other_child_model, foreign_key: :model_id
          has_one :very_polymorphic_sibling_model, as: :other_model, class_name: 'VeryPolymorphicSiblingModel'
        end

        #
        # Cousin of second degree child
        #
        define_model 'PolymorphicSiblingModel' do
          self.table_name = 'child_models'

          belongs_to :model, polymorphic: true
          has_one :unowned_model, foreign_key: :model_id
        end

        #
        # Cousin of second degree child
        #
        define_model 'VeryPolymorphicSiblingModel' do
          self.table_name = 'other_child_models'

          belongs_to :model, polymorphic: true
          belongs_to :other_model, polymorphic: true

        end


        #
        # Top level model, parent of Tenant Model
        #
        define_model 'UnownedModel' do
          has_many :tenant_models, foreign_key: :parent_id,
                                   class_name: 'TenantModel'
          # has_many :uncle_models, foreign_key: :parent_id
        end

        #
        # Bottom level model, has and belons to many 2nd degree child
        #
        define_model 'BottomModel' do
          self.table_name = 'models'

          has_and_belongs_to_many :other_child_models,
                                  class_name: 'OtherChildModel',
                                  join_table: 'model_models',
                                  foreign_key: :child_id,
                                  association_foreign_key: :parent_id
        end

        TenantModel.send :tenant
      end

      it 'should have added has_one :tenant_model to other child model' do
        expect(OtherChildModel.new).to have_one(:tenant_model).through(:child_model)
      end

      it 'should have added has_many :tenant_models to BottomModel' do
        expect(BottomModel.new).to have_many(:tenant_models).through :other_child_models
      end

      it 'should have created a has_one :tenant_model to SiblingModel' do
        expect(SiblingModel.new).to have_one(:tenant_model).through :other_child_model
      end

      it 'should not have set a :tenant_model on polymorphic association' do
        expect(PolymorphicSiblingModel.new).not_to have_one(:tenant_model)
      end

      it 'should have added has_many :tenant_models to UncleModel' do
        expect(UncleModel.new).not_to have_many(:tenant_models).through :other_child_models
      end

      %w[ChildModel OtherChildModel BottomModel SiblingModel].each do |model|
        it "should have added a scope with_tenants to #{model}" do
          expect(model.constantize).to respond_to :with_tenant_models
        end
      end

      %w[ChildModel OtherChildModel BottomModel SiblingModel].each do |model|
        it "should have added a scope where_tenants to #{model}" do
          expect(model.constantize).to respond_to :where_tenant_models_among
        end
      end

      it 'creates a has_many users_tenant_models' do
        expect(Strongbolt::Configuration.user_class.constantize.new).to have_many(:users_tenant_models)
          .dependent(:delete_all)
      end

      it 'creates a has_many relationship on the User defined' do
        expect(Strongbolt::Configuration.user_class.constantize.new).to have_many(:tenant_models).through :users_tenant_models
      end

      it 'creates a relationship on the user to get accessible tenants' do
        expect(Strongbolt::Configuration.user_class.constantize.new).to respond_to :accessible_tenant_models
      end

      it 'should have added models to Capability::Models' do
        expect(Strongbolt::Capability.models).to be_present
        expect(Strongbolt::Capability.models.size).to be > 0
      end

      it 'should not raise an error' do
        expect do
          TenantModel.send :tenant
        end.not_to raise_error Strongbolt::DirectAssociationNotConfigured
      end

    end

    #
    # When an association lacks an inverse (none configured and none found)
    #

    context 'when an association lacks an inverse' do
      before(:all) do
        #
        # Tenant Model
        #
        define_model 'TenantModel' do
          self.table_name = 'models'

          has_many :child_models
        end

        #
        # Direct child to Tenant Model
        #
        define_model 'ChildModel' do
          self.table_name = 'child_models'

          belongs_to :tenant_model, foreign_key: :model_id

          has_many :other_child_models
        end

        define_model 'OtherChildModel' do
          self.table_name = 'child_models'
        end
      end

      it 'should raise an error' do
        expect do
          TenantModel.send :tenant
        end.to raise_error Strongbolt::InverseAssociationNotConfigured
      end
    end

    #
    # When a direct association lacks a reference to the tenant
    #

    context 'when an association lacks an inverse' do
      before(:all) do
        #
        # Tenant Model
        #
        define_model 'TenantModel' do
          self.table_name = 'models'

          has_many :child_models
        end

        #
        # Direct child to Tenant Model
        #
        define_model 'ChildModel' do
          self.table_name = 'child_models'
        end
      end

      it 'should raise an error' do
        expect do
          TenantModel.send :tenant
        end.to raise_error Strongbolt::DirectAssociationNotConfigured
      end
    end
  end
end
