class ResolverController < ApplicationController

  set_access_control  :public => [:resolve_edit, :resolve_readonly]


  def resolve_edit
    if params.has_key? :uri
      resolver = Resolver.new(params[:uri])
      redirect_to resolver.edit_uri
    else
      unauthorised_access
    end
  end


  def resolve_readonly
    if params.has_key? :uri
      resolver = Resolver.new(params[:uri])

      # switch repositories if required
      # (only happens when resolver is hit via public app)
      if resolver.repo_id != session[:repo_id]
        selected = @repositories.find {|r| r.id == resolver.repo_id}

        raise RecordNotFound.new if selected.nil?

        session[:repo] = selected.uri
        session[:repo_id] = selected.id
      end

      redirect_to resolver.view_uri
    else
      unauthorised_access
    end
  end


end