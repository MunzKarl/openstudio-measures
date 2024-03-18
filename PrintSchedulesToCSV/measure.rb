require 'csv'

# Start the measure
class PrintSchedulesToCSV < OpenStudio::Measure::ModelMeasure

  # Define the name of the measure
  def name
    return "PrintSchedulesToCSV"
  end

  # Define the description of the measure
  def description
    return "Exports all schedules in the model to a CSV file with their names and handles."
  end

  # Define the model inputs for the measure
  def model_inputs
    return []
  end

  # Define the model outputs for the measure
  def model_outputs
    return []
  end

  # Define the run method for the measure
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Create an array to store the schedule data
    schedule_data = []

    # Get all schedules in the model
    schedules = model.getSchedules

    # Loop through each schedule
    schedules.each do |schedule|
      schedule_data << [schedule.name.to_s, schedule.handle.to_s]
    end

    # Create the CSV file
    CSV.open("#{Dir.pwd}/schedules.csv", "wb") do |csv|
      csv << ["Name", "Handle"]
      schedule_data.each do |row|
        csv << row
      end
    end

    # Inform the user that the CSV file has been created
    runner.registerInfo("CSV file with schedules created successfully.")

    return true
  end
end

# Register the measure
PrintSchedulesToCSV.new.registerWithApplication
