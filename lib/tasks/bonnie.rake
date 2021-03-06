namespace :bonnie do
  namespace :users do

    desc %{Grant an existing bonnie user administrator privileges.

    You must identify the user by USER_ID or EMAIL:

    $ rake bonnie:users:grant_admin USER_ID=###
    or
    $ rake bonnie:users:grant_admin EMAIL=xxx}
    task :grant_admin => :environment do
      user = User.find_by email: ENV['EMAIL']
      user.grant_admin()
      puts "#{ENV['EMAIL']} is now an administrator."
    end

    desc %{Remove the administrator role from an existing bonnie user.

    You must identify the user by USER_ID or EMAIL:

    $ rake bonnie:users:revoke_admin USER_ID=###
    or
    $ rake bonnie:users:revoke_admin EMAIL=xxx}
    task :revoke_admin => :environment do
      user = User.find_by email: ENV["EMAIL"]
      user.revoke_admin()
      puts "#{ENV['EMAIL']} is no longer an administrator."
    end

    desc %{Grant an existing bonnie user portfolio privileges.

    You must identify the user by USER_ID or EMAIL:

    $ rake bonnie:users:grant_portfolio USER_ID=###
    or
    $ rake bonnie:users:grant_portfolio EMAIL=xxx}
    task :grant_portfolio => :environment do
      user = User.find_by email: ENV['EMAIL']
      user.grant_portfolio()
      puts "#{ENV['EMAIL']} is now a portfolio user."
    end

    desc %{Remove the portfolio role from an existing bonnie user.

    You must identify the user by USER_ID or EMAIL:

    $ rake bonnie:users:revoke_portfolio USER_ID=###
    or
    $ rake bonnie:users:revoke_portfolio EMAIL=xxx}
    task :revoke_portfolio => :environment do
      user = User.find_by email: ENV["EMAIL"]
      user.revoke_portfolio()
      puts "#{ENV['EMAIL']} is no longer a portfolio user."
    end

    desc 'Associate the currently loaded measures with the first User; use EMAIL=<user email> to select another user'
    task :associate_user_with_measures => :environment do
      user_email = ENV['EMAIL'] || User.first.email
      user = User.where(email: user_email).first
      puts "Associating measures with #{user.email}"
      Measure.all.update_all(user_id: user.id, bundle_id: user.bundle_id)
    end

    desc 'Associate the currently loaded measures with the first User; use EMAIL=<user email> to select another user'
    task :associate_user_with_valuesets => :environment do
      user_email = ENV['EMAIL'] || User.first.email
      user = User.where(email: user_email).first
      puts "Associating Valuesets with #{user.email}"
      HealthDataStandards::SVS::ValueSet.all.update_all(user_id: user.id, bundle_id: user.bundle_id)
    end

    desc 'Associate the currently loaded patients with the first User; use EMAIL=<user email> to select another user'
    task :associate_user_with_patients => :environment do
      user_email = ENV['EMAIL'] || User.first.email
      user = User.where(email: user_email).first
      puts "Associating patients with #{user.email}"
      Record.all.update_all(user_id: user.id, bundle_id: user.bundle_id)
    end


    desc 'Make sure all of the users in the system have a bundle'
    task :ensure_users_have_bundles => :environment do
      User.all.each do |u|
        unless u.bundle 
            b = HealthDataStandards::CQM::Bundle.new(title: "Bundle for user #{u.id.to_s}", version: "1")
            b.save
            u.bundle = b
            u.save
        end
      end
    end

  end

  namespace :db do

    desc 'Reset DB; by default pulls from bonnie-dev.mitre.org:bonnie-production-gold; use HOST=<host> DB=<db> for another; DEMO=true prunes measures'
    task :reset_legacy => :environment do
      
      host = ENV['HOST'] || 'bonnie-dev.mitre.org'
      source_db = ENV['DB'] || 'bonnie-production-gold'
      dest_db = Mongoid.default_session.options[:database]
      puts "Resetting #{dest_db} from #{host}:#{source_db}"
      Mongoid.default_session.with(database: dest_db) { |db| db.drop }
      Mongoid.default_session.with(database: 'admin') { |db| db.command copydb: 1, fromhost: host, fromdb: source_db, todb: dest_db }
      puts "Dropping unneeded collections: measures, bundles, patient_cache, query_cache..."
      Mongoid.default_session['bundles'].drop()
      Mongoid.default_session['measures'].drop()
      Mongoid.default_session['query_cache'].drop()
      Mongoid.default_session['patient_cache'].drop()
      Rake::Task['bonnie:users:ensure_users_have_bundles'].invoke
      Rake::Task['bonnie:patients:update_measure_ids'].invoke
      Rake::Task['bonnie:users:associate_user_with_measures'].invoke
      Rake::Task['bonnie:users:associate_user_with_patients'].invoke
      Rake::Task['bonnie:users:associate_user_with_valuesets'].invoke
      Rake::Task["bonnie:patients:update_source_data_criteria"].invoke
      if ENV['DEMO'] == 'true'
        puts "Deleting non-demo measures and patients"
        demo_measure_ids = Measure.in(measure_id: ['0105', '0069']).pluck('hqmf_set_id') # Note: measure_id is nqf, id is hqmf_set_id!
        Measure.nin(hqmf_set_id: demo_measure_ids).delete
        Record.nin(measure_ids: demo_measure_ids).delete
      end
      Rake::Task['bonnie:patients:reset_expected_values'].invoke
      if ENV['DEMO'] == 'true'
        puts "Updating expected values for demo"
        measure_id = Measure.where(measure_id: '0105').first.hqmf_set_id
        patient = Record.where(first: 'BH_Adult', last: 'C').first
        patient.expected_values << {measure_id: measure_id, population_index: 0, IPP: 1, DENOM: 1, NUMER: 0, DENEX: 0}
        patient.expected_values << {measure_id: measure_id, population_index: 1, IPP: 1, DENOM: 1, NUMER: 0, DENEX: 0}
        patient.save!
        patient = Record.where(first: 'BH_Adult', last: 'D').first
        patient.expected_values << {measure_id: measure_id, population_index: 0, IPP: 1, DENOM: 1, NUMER: 1, DENEX: 0}
        patient.expected_values << {measure_id: measure_id, population_index: 1, IPP: 1, DENOM: 1, NUMER: 0, DENEX: 0}
        patient.save!
      end
      Rake::Task['bonnie:measures:pregenerate_js'].invoke
      User.each do |u|
        u.approved = true
        u.save
      end
    end

    desc 'Reset DB; by default pulls from bonnie-dev.mitre.org:bonnie2-production-gold; use HOST=<host> DB=<db> for another; DEMO=true prunes measures'
    task :reset => :environment do

      host = ENV['HOST'] || 'bonnie-dev.mitre.org'
      source_db = ENV['DB'] || 'bonnie2-production-gold'
      dest_db = Mongoid.default_session.options[:database]
      puts "Resetting #{dest_db} from #{host}:#{source_db}"
      Mongoid.default_session.with(database: dest_db) { |db| db.drop }
      Mongoid.default_session.with(database: 'admin') { |db| db.command copydb: 1, fromhost: host, fromdb: source_db, todb: dest_db }
      if ENV['DEMO'] == 'true'
        puts "Deleting non-demo measures and patients"
        demo_measure_ids = Measure.in(measure_id: ['0105', '0069']).pluck('hqmf_set_id') # Note: measure_id is nqf, id is hqmf_set_id!
        Measure.nin(hqmf_set_id: demo_measure_ids).delete
        Record.nin(measure_ids: demo_measure_ids).delete
      end
    end

    DUMP_TIME_FORMAT = "%Y-%m-%d-%H-%M-%S"

    desc 'Dumps the local database matching the supplied RAILS_ENV'
    task :dump => :environment do
      db = Mongoid.default_session.options[:database]
      datestamp = Time.now.strftime(DUMP_TIME_FORMAT)
      path = Rails.root.join 'db', 'backups'
      file = "#{db}-#{datestamp}"
      command = "mkdir -p #{path} && mongodump --db #{db} --out #{path.join(file)} && cd #{path} && tar czf #{file}.tgz #{file} && rm -r #{file}"
      puts command
      system command
    end

    desc 'Prune database dumps to keep daily dumps for last month, weekly dumps before that, for the supplied RAILS_ENV'
    task :prune_dumps => :environment do
      puts "Pruning database dumps for #{Rails.env}"
      def file_time(filename)
        return unless match = filename.match(%r(-([0-9-]+).tgz))
        Time.strptime(match[1], DUMP_TIME_FORMAT)
      end
      path = Rails.root.join 'db', 'backups', '*.tgz'
      files = Dir.glob(path).select { |f| file_time(f) } # Only interested in files where we can determine time
      # File from older than past month, keep most recent weekly
      files.select { |f| file_time(f) < 1.month.ago }.group_by { |f| file_time(f).strftime('%Y week %V') }.each do |week, ff|
        sorted = ff.sort_by { |f| file_time(f) }
        sorted[0..-2].each do |f|
          puts "Deleting #{f}"
          system "rm #{f}"
        end
        puts "Keeping #{sorted.last}"
      end
      # Files from past month, keep most recent daily
      files.select { |f| file_time(f) >= 1.month.ago }.group_by { |f| file_time(f).strftime('%Y-%m-%d') }.each do |day, ff|
        sorted = ff.sort_by { |f| file_time(f) }
        sorted[0..-2].each do |f|
          puts "Deleting #{f}"
          system "rm #{f}"
        end
        puts "Keeping #{sorted.last}"
      end
    end

  end

  namespace :test do
    desc 'Deletes all measures except for failing Cypress measures and CV measures; Use after running a bonnie:load:mitre_bundle rake task.'
    task :prune_db => :environment do
      puts "Reducing imported measures"
      some_measure_ids = Measure.in(measure_id: ['0710', '0389', 'ADE_TTR', '0497', '0495', '0496']).pluck('hqmf_set_id')
      Measure.nin(hqmf_set_id: some_measure_ids).delete
    end
  end

  namespace :measures do
    desc 'Pre-generate measure JavaScript and cache in the DB'
    task :pregenerate_js => :environment do
      puts "Pre-generating measure JavaScript"
      Measure.each do |measure|
        puts "\tGenerating JavaScript for '#{measure.title}'"
        measure.generate_js
      end
    end
  end

  namespace :patients do

    desc "Updated source_data_criteria to include title and description from measure(s)"
    task :update_source_data_criteria=> :environment do
      puts "Updating patient source_data_criteria to include title and description"
      Record.each do |patient|
        measures = Measure.in(hqmf_set_id:  patient.measure_ids).to_a
        puts "\tUpdating source data criteria for record #{patient.first} #{patient.last}"
        patient.source_data_criteria.each do |patient_data_criteria|
          measures.each do |measure|
            measure_data_criteria = measure.source_data_criteria[patient_data_criteria['id']]
            if  measure_data_criteria && measure_data_criteria['code_list_id'] == patient_data_criteria['oid']
              patient_data_criteria['hqmf_set_id'] = measure['hqmf_set_id']
              patient_data_criteria['cms_id'] = measure['cms_id']
              patient_data_criteria['code_list_id'] = patient_data_criteria['oid']
              patient_data_criteria['title'] = measure_data_criteria['title']
              patient_data_criteria['description'] = measure_data_criteria['description']
              patient_data_criteria['negation'] = patient_data_criteria['negation'] == "true"
              patient_data_criteria['type'] = measure_data_criteria['type']
              patient_data_criteria['end_date']=nil if patient_data_criteria['end_date'] == 32503698000000

              # FIXME Not sure why field_values has no keys now, did the Cypress patient set change?
              unless patient_data_criteria['field_values'].blank?
                patient_data_criteria['field_values'].keys.each do |key|
                  field_value = patient_data_criteria['field_values'][key]
                  if (field_value['type'] == 'TS')
                    field_value['value'] = Time.strptime(field_value['value'],"%m/%d/%Y %H:%M").to_i*1000 rescue field_value['value']
                  end
                end
              end if patient_data_criteria['field_values']
            end
          end
        end
        patient.save
      end

    end


    desc 'Update measure ids from NQF to HQMF.'
    task :update_measure_ids => :environment do
      puts "Updating patient measure_ids from NQF to HQMF"
      Record.each do |patient|
        patient.measure_ids.map! { |id| Measure.or({ measure_id: id }, { hqmf_id: id }, { hqmf_set_id: id }).first.try(:hqmf_set_id) }.compact!
        patient.save
        puts "\tUpdated patient #{patient.first} #{patient.last}."
      end
    end

    desc 'Reset expected_values hash.'
    task :reset_expected_values => :environment do
      puts "Resetting expected_values hash for all patients to []"
      Record.each do |patient|
        patient.expected_values = []
        patient.save
        puts "\tReset expected_values for patient #{patient.first} #{patient.last}."
      end
    end
  end
end
