require 'spec_helper'

describe Spree::Order do
  let(:user) { mock_model(Spree::User, :email => 'test-user@pos.com') }
  [:state, :is_pos, :completed_at, :payment_state].each do |attribute|
    it { should allow_mass_assignment_of attribute }
  end

  before do
    @order = Spree::Order.create! 
    @order.stub(:total).and_return 100
    @variant = Spree::Variant.new
    @shipment = @order.shipments.new
    @line_item = @order.line_items.new(:quantity => 1)
    @line_item.variant = @variant
    @payment = mock_model(Spree::Payment)
    @payments = [@payment]
    @payments.stub(:delete_all).and_return(true)
    @order.stub(:payments).and_return(@payments)
    @content = Spree::OrderContents.new(@order)
    @order.stub(:contents).and_return(@content)
    @content.stub(:remove).with(@variant, 1, @shipment).and_return(true)
  end

  context 'scopes' do
    before :each do
      @paid_order = Spree::Order.create!(:total => 100)
      @paid_order.update_column(:payment_state,'paid')
      @unpaid_pos_order = Spree::Order.create!(:is_pos => true, :payment_state => 'checkout')
      @paid_pos_order = Spree::Order.create!(:is_pos => true, :payment_state => 'paid')
      @paid_pos_order.update_column(:payment_state,'paid')    
      @unpaid_order = Spree::Order.create!(:payment_state => 'checkout')
    end

    it { Spree::Order.pos.should match_array([@unpaid_pos_order, @paid_pos_order]) }
    it { Spree::Order.unpaid.should match_array([@unpaid_pos_order, @unpaid_order]) }
    it { Spree::Order.unpaid_pos_order.should eq([@unpaid_pos_order]) }
  end

  describe '#clean!' do
    it { @payments.should_receive(:delete_all).and_return(true) }
    it { @line_item.should_receive(:variant).and_return(@variant) }
    it { @line_item.should_receive(:quantity).and_return(1) }
    it { @content.should_receive(:remove).with(@variant, 1, @shipment).and_return(true) }
    
    after { @order.clean! }
  end

  describe '#complete_via_pos' do
    before do
      @order.stub(:create_tax_charge!).and_return(true)
      @order.stub(:pending_payments).and_return(@payments)
      @payment.stub(:capture!).and_return(true)
      @shipment.stub(:finalize_pos).and_return(true)
      @order.stub(:deliver_order_confirmation_email).and_return(true)
      @order.stub(:save!).and_return(true)
    end

    it { @order.should_receive(:touch).with(:completed_at) }
    it { @order.should_receive(:create_tax_charge!).and_return(true) }
    it { @order.should_receive(:pending_payments).and_return(@payments) }
    it { @payment.should_receive(:capture!).and_return(true) }
    it { @shipment.should_receive(:finalize_pos).and_return(true) }
    it { @order.should_receive(:deliver_order_confirmation_email).and_return(true) }
    it { @order.should_receive(:save!).and_return(true) }
    
    after { @order.complete_via_pos }
  end

  describe '#assign_shipment_for_pos' do
    context '#is_pos?' do
      before do
        @order.stub(:is_pos?).and_return(true)
        @stock_location = mock_model(Spree::StockLocation)
        Spree::StockLocation.stub(:active).and_return([@stock_location])
        @pos_shipping_method = mock_model(Spree::ShippingMethod)
        Spree::ShippingMethod.stub(:where).and_return([@pos_shipping_method])
        @order.stub_chain(:shipments, :build).and_return(@shipment)
        @shipment.stub(:save!).and_return(true)
      end

      describe 'method calls' do
        it { @order.should_receive(:is_pos?).and_return(true) }
        it { @shipment.should_receive(:save!).and_return(true) }        

        after { @order.assign_shipment_for_pos }
      end

      describe 'assigns' do
        before { @order.assign_shipment_for_pos }
        
        it { @shipment.shipping_methods.should eq([@pos_shipping_method]) }
        it { @shipment.stock_location.should eq(@stock_location) }
      end
    end

    context '#is_pos? false' do
      before { @order.stub(:is_pos?).and_return(false) }
      
      describe 'method calls' do
        it { @order.should_receive(:is_pos?).and_return(false) }
        it { @order.should_not_receive(:shipments) }
        it { Spree::ShippingMethod.should_not_receive(:where) }
        it { Spree::StockLocation.should_not_receive(:active) }        

        after { @order.assign_shipment_for_pos }
      end      
    end
  end

  describe '#save_payment_for_pos' do
    before do
      @payments.stub(:delete_all).and_return(true)
      @payments.stub(:create).with(:amount => 100, :payment_method_id => 1, :card_name => 'MasterCard').and_return(@payment)
    end
    it { @payments.should_receive(:delete_all).and_return(true) }
    it { @payments.should_receive(:create).with(:amount => 100, :payment_method_id => 1, :card_name => 'MasterCard').and_return(@payment) }
    after { @order.save_payment_for_pos(1, 'MasterCard') }
  end

  describe '#associate_user_for_pos' do
    context 'user with email exists' do
      before do
        Spree::User.stub(:where).with(:email => user.email).and_return([user])
      end

      context 'when user is valid' do
        before { user.stub(:valid?).and_return(true) }

        it { Spree::User.should_receive(:where).with(:email => user.email).and_return([user]) }
        it { Spree::User.should_not_receive(:create_with_random_password) }
        it { @order.should_receive(:email=).with(user.email).and_return(true) }
        after { @order.associate_user_for_pos(user.email) }
      end

      context 'when user is not valid' do
        before { user.stub(:valid?).and_return(false) }
        
        it { Spree::User.should_receive(:where).with(:email => user.email).and_return([user]) }
        it { Spree::User.should_not_receive(:create_with_random_password) }        
        it { @order.should_not_receive(:email=).with(user.email) }
        after { @order.associate_user_for_pos(user.email) }
      end
      
      it { @order.associate_user_for_pos(user.email).should eq(user) }
    end

    context 'user with email does not exist' do
      before do
        @new_user = mock_model(Spree::User)
        Spree::User.stub(:create_with_random_password).with('new-user@pos.com').and_return(@new_user)
      end

      context 'when new user is valid' do
        before { @new_user.stub(:valid?).and_return(true) }

        it { Spree::User.should_receive(:where).with(:email => 'new-user@pos.com').and_return([]) } 
        it { Spree::User.should_receive(:create_with_random_password).with('new-user@pos.com').and_return(@new_user) }
        it { @order.should_receive(:email=).with('new-user@pos.com').and_return(true) }
        
        after { @order.associate_user_for_pos('new-user@pos.com') }
      end

      context 'when new user is not valid' do
        before { @new_user.stub(:valid?).and_return(false) }
        
        it { Spree::User.should_receive(:where).with(:email => 'new-user@pos.com').and_return([]) } 
        it { Spree::User.should_receive(:create_with_random_password).with('new-user@pos.com').and_return(@new_user) }
        it { @order.should_not_receive(:email=).with(@new_user.email) }
        
        after { @order.associate_user_for_pos('new-user@pos.com') }
      end

      it { @order.associate_user_for_pos('new-user@pos.com').should eq(@new_user) }
    end
  end
end