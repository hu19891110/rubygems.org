namespace :gemcutter do
  namespace :index do
    desc "Update the index"
    task update: :environment do
      require 'benchmark'
      Benchmark.bm do |b|
        b.report("update index") { Indexer.new.perform }
      end
    end
  end

  namespace :import do
    desc 'Bring the gems through the gemcutter process'
    task process: :environment do
      gems = Dir[File.join(ARGV[1] || "#{Gem.path.first}/cache", "*.gem")].sort.reverse
      puts "Processing #{gems.size} gems..."
      gems.each do |path|
        puts "Processing #{path}"
        cutter = Pusher.new(nil, File.open(path))

        cutter.process
        puts cutter.message unless cutter.code == 200
      end
    end
  end

  namespace :checksums do
    desc "Initialize missing checksums."
    task init: :environment do
      without_sha256 = Version.where(sha256: nil)
      mod = ENV['shard']
      without_sha256.where("id % 4 = ?", mod.to_i) if mod

      total = without_sha256.count
      i = 0
      without_sha256.find_each do |version|
        version.recalculate_sha256!
        i += 1
        print format("\r%.2f%% (%d/%d) complete", i.to_f / total * 100.0, i, total)
      end
      puts
      puts "Done."
    end

    desc "Check existing checksums."
    task check: :environment do
      failed = false
      Version.find_each do |version|
        actual_sha256 = version.recalculate_sha256
        if version.sha256 != actual_sha256
          puts "#{version.full_name}.gem has sha256 '#{actual_sha256}', " \
            "but '#{version.sha256}' was expected."
          failed = true
        end
      end

      exit 1 if failed
    end
  end

  namespace :rubygems do
    desc "Update the db download count with the redis value"
    task update_download_counts: :environment do
      Version.find_in_batches do |group|
        group.each do |version|
          rubygem = version.rubygem
          begin
            unless GemDownload.exists?(rubygem_id: version.rubygem_id, version_id: 0)
              GemDownload.create!(rubygem_id: version.rubygem_id, version_id: 0, count: rubygem.downloads || 0)
            end
          rescue ActiveRecord::RecordNotUnique
            p "Skipping #{version.full_name}"
          end
          begin
            unless GemDownload.exists?(rubygem_id: version.rubygem_id, version_id: version.id)
              GemDownload.create!(rubygem_id: version.rubygem_id, version_id: version.id, count: version.downloads_count || 0)
            end
          rescue ActiveRecord::RecordNotUnique
            p "Skipping #{version.full_name}"
          end
        end
      end
    end
  end

  desc "Move all but the last 2 days of version history to SQL"
  task migrate_history: :environment do
    Download.copy_all_to_sql do |t, c, v|
      puts "#{c} of #{t}: #{v.full_name}"
    end
  end

  namespace :metadata do
    desc "Backfill old gem versions with metadata."
    task backfill: :environment do
      without_metadata = Version.where("metadata = ''")
      mod = ENV['shard']
      without_metadata = without_metadata.where("id % 4 = ?", mod.to_i) if mod

      total = without_metadata.count
      i = 0
      puts "Total: #{total}"
      without_metadata.find_each do |version|
        version.recalculate_metadata!
        i += 1
        print format("\r%.2f%% (%d/%d) complete", i.to_f / total * 100.0, i, total)
      end
      puts
      puts "Done."
    end
  end
end
