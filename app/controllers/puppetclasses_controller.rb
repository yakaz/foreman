require 'foreman/controller/environments'

class PuppetclassesController < ApplicationController
  include Foreman::Controller::Environments
  include Foreman::Controller::AutoCompleteSearch
  before_filter :find_from_param, :only => [:edit, :update, :destroy, :assign]
  before_filter :setup_search_options, :only => :index

  def index
    begin
      values = Puppetclass.search_for(params[:search], :order => params[:order])
    rescue => e
      error e.to_s
      values = Puppetclass.search_for ""
    end

    respond_to do |format|
      format.html do
        @puppetclasses = values.paginate :page => params[:page], :include => [:environment, :hostgroups]
        @host_counter = Host.count(:group => :puppetclass_id, :joins => :puppetclasses, :conditions => {:puppetclasses => {:id => @puppetclasses}})
        @keys_counter = LookupKey.count(:group => :puppetclass_id, :conditions => {:puppetclass_id => @puppetclasses})
      end
      format.json { render :json => Puppetclass.classes2hash(values.all(:select => "name, id")) }
    end
  end

  def new
    @puppetclass = Puppetclass.new
  end

  def create
    @puppetclass = Puppetclass.new(params[:puppetclass])
    if @puppetclass.save
      notice "Successfully created puppetclass."
      redirect_to puppetclasses_url
    else
      render :action => 'new'
    end
  end

  def edit
  end

  # form AJAX methods
  def parameters
    puppetclass = Puppetclass.find(params[:puppetclass_id])
    host = Host.find_by_id(params[:host_id])
    render :partial => "puppetclasses/class_parameters", :locals => {:klass => puppetclass, :host => host, :host_facts => host.facts_hash}
  end

  def update
    if @puppetclass.update_attributes(params[:puppetclass])
      notice "Successfully updated puppetclass."
      redirect_to puppetclasses_url
    else
      render :action => 'edit'
    end
  end

  def destroy
    if @puppetclass.destroy
      notice "Successfully destroyed puppetclass."
    else
      error @puppetclass.errors.full_messages.join("<br/>")
    end
    redirect_to puppetclasses_url
  end

  private
  def find_from_param
    (@puppetclass = Puppetclass.from_param params[:id]) or return not_found
  end

end
