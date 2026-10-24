Saboteur.configure do |c|
  c.include = ["app/**/*.rb"]
  c.exclude = [
    "app/models/application_record.rb",
    "app/controllers/application_controller.rb",
    "app/jobs/application_job.rb",
    "app/mailers/application_mailer.rb",
  ]
  c.require = ["./config/environment"]
  c.rails = true
  c.jobs = 1
  c.partial_coverage = "use"
end
