# config/initializers/warden_hooks.rb
Warden::Manager.after_set_user do |user, auth, opts|
  if opts[:event] == :authentication
    # Use .delay to push this to the background table
    ConnectionAuditJob.new(
      user.class.name,
      user.id,
      auth.request.remote_ip,
      auth.request.user_agent
    ).delay.perform
  end
end
