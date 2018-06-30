#!/usr/bin/env ruby

OUTPUT_DIR = "Output/"

path_list = ARGV[0]
path_dir = ARGV[1]

if path_list.nil? || path_dir.nil?
    puts "Usage: \t\t\033[1m" + __FILE__ + "\033[0m <path/to/list> <path/to/directory>"
    puts "Example: \t\033[1m" + __FILE__ + "\033[0m Input/example.csv ~/collection"
    abort
end

should_abort = false

if !File.file?(path_list)
    puts "⛔️ List of phrases not found"
    should_abort = true
end

if !File.directory?(path_dir)
    puts "⛔️ Directory \033[1m" + path_dir + "\033[0m not found"
    should_abort = true
end

if should_abort
    abort
end

File.open(path_list).each(sep="\n") do |line|
    line = line.tr("\n", "")
    puts "🔍 Searching " + line + "..."
    cmd = "grep -rnw \"" + path_dir +"\" -e \"" + line + "\""
    found_path = OUTPUT_DIR + File.basename(path_list) + "-found"
    not_found_path = OUTPUT_DIR + File.basename(path_list) + "-notFound"
    value = `#{cmd}`
    if value.length > 0
        puts "\t✅ " + "\033[1m" + line + "\033[0m found"
        File.open(found_path, "a") do |file|
            file.puts line
        end
    else
        puts "\t⛔️ " + "\033[1m" + line + "\033[0m not found"
        File.open(not_found_path, "a") do |file|
            file.puts line
        end
    end
end
