["Generating Energy Flow",
 "Fundamentals of Tai Chi Chuan",
 "Cosmic Shower",
 "108-Pattern Yang style Tai Chi Chuan",
 "Abdominal Breathing",
 "Flowing Water Floating Clouds",
 "Merging with the Cosmos",
 "Wudang Tai Chi Chuan"].each do |course|
  attendees = Registration.in(courses: course).all.map(&:name)
  puts "#{course}(#{attendees.size})\n---\n#{attendees.join("\n")}\n\n"
end
