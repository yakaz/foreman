class LookupKeysController < ApplicationController
  include Foreman::Controller::AutoCompleteSearch
  before_filter :find_from_param, :except => [:index, :merge]
  before_filter :setup_search_options, :only => :index

  def index
    if params[:search] =~ /^puppetclass = (\d+)$/
      params[:search] = "puppetclass_id = #{$1}"
    end
    begin
      values = LookupKey.search_for(params[:search], :order => params[:order])
    rescue => e
      error e.to_s
      values = LookupKey.search_for ""
    end

    respond_to do |format|
      format.html do
        @lookup_keys = values.paginate(:page => params[:page], :include => [:lookup_values, :puppetclass])
      end
      format.json { render :json => values}
    end
  end

  def show
    if (name = params[:host_id]).blank? or (host = Host.find_by_name(name)).blank?
      value = @lookup_key
    else
      value = { :value => @lookup_key.value_for(host) }
    end

    respond_to do |format|
      format.json { render :json => value }
    end
  end

  def new
    @lookup_key = LookupKey.new
  end

  def create
    @lookup_key = LookupKey.new(params[:lookup_key])
    if @lookup_key.save
      process_success
    else
      process_error
    end
  end

  def edit
  end

  def update
    if @lookup_key.update_attributes(params[:lookup_key])
      process_success
    else
      process_error
    end
  end

  def destroy
    if @lookup_key.destroy
      process_success
    else
      process_error
    end
  end

  def merge
    if params[:fields_for]
      params[:id] = params.delete :fields_for
      find_from_param
      render :partial => 'lookup_keys/merge_fields'
    end
  end

  private
  def find_from_param
    if params[:id]
      @lookup_key = LookupKey.from_param(params[:id])
      not_found and return if @lookup_key.blank?
    end
  end
end
