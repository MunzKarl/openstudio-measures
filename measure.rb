# load dependencies
require 'csv'
require 'json'

# start the measure
class AddAndApplyIntervalScheduleFromFile < OpenStudio::Ruleset::ModelUserScript

  # display name
  def name
    return "Add and Apply ScheduleInterval or ScheduleFile From File"
  end
  # description
  def description
    return "This measure adds a schedule object from a file of interval data and can replace an existing schedule in the file with it. It also lets you specify which column from the CSV should be read so you can store multiple columns of data in one file. Allows beginning rows to be ignored in case there is header information present."
  end
  # modeler description
  def modeler_description
    return "This measure adds a ScheduleInterval object from a user-specified .csv file. The measure supports hourly, 15 min, 5 min, and 1 min interval data for leap and non-leap years.  The .csv file must contain only schedule values with 8760, 8784, 35040, 35136, 105120, 105408, 525600, or 527040 rows specified. See the example .csv files in the tests directory of this measure. It also lets you specify which column from the CSV should be read so you can store multiple columns of data in one file. Allows beginning rows to be ignored in case there is header information present."
  end
  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
    sch_handles = OpenStudio::StringVector.new
    sch_display_names = OpenStudio::StringVector.new
    # populating the list with two blanks so that we can have a blank default
    sch_handles << model.getBuilding.handle.to_s
    sch_display_names << ""
    # Getting a list of all the schedules in the model
    schedules_hash = {}
    model.getSchedules.each do |sch|
      schedules_hash[sch.name.to_s] = sch
    end
    # Looping to sort schedules and build the arrays
    schedules_hash.sort.map do |sch_name, sch|
      sch_handles << sch.handle.to_s
      sch_display_names << sch_name
    end

    # adding choice to use schedule:file instead of interval schedule
    use_schedule_file = OpenStudio::Ruleset::OSArgument::makeBoolArgument('use_schedule_file', true)
    use_schedule_file.setDisplayName("Use a Schedule:File object instead of Schedule:Interval?")
    use_schedule_file.setDescription("Schedule:file will load faster. Turn off if the model crashes.")
    use_schedule_file.setDefaultValue(true)
    args << use_schedule_file
    
    # adding choice to replace schedule
    replace_schedule = OpenStudio::Ruleset::OSArgument::makeBoolArgument('replace_schedule', true)
    replace_schedule.setDisplayName("Replace a schedule in the model?")
    replace_schedule.setDefaultValue(true)
    args << replace_schedule

    # schedule to be replaced
    old_schedule = OpenStudio::Measure::OSArgument.makeChoiceArgument('old_schedule', sch_handles, sch_display_names, true)
    old_schedule.setDisplayName('If the above box is checked, choose the schedule to be replaced.')
    old_schedule.setDefaultValue("")
    args << old_schedule

    # make an argument for schedule name
    new_schedule_name = OpenStudio::Ruleset::OSArgument::makeStringArgument('new_schedule_name', true)
    new_schedule_name.setDisplayName("New Schedule Name (if you're not replacing an old schedule):")
    new_schedule_name.setDefaultValue('')
    args << new_schedule_name

    # make an argument for directory to look for the file
    file_dir = OpenStudio::Ruleset::OSArgument.makeStringArgument('file_dir', false)
    file_dir.setDisplayName('Enter the path to the directory where the data file is stored (Leave this blank it subsequent runtime measures to reuse the same path):')
    file_dir.setDescription("Example: 'C:\\Projects\\data'")
    file_dir.setDefaultValue("")
    args << file_dir

    # make an argument for file name
    file_name = OpenStudio::Ruleset::OSArgument.makeStringArgument('file_name', false)
    file_name.setDisplayName('Enter the name of the CSV file (Leave this blank it subsequent runtime measures to reuse the same name):')
    file_name.setDescription("Example: 'values.csv'")
    file_name.setDefaultValue("")
    args << file_name

    # Make an argument for column to read
    data_column = OpenStudio::Ruleset::OSArgument.makeIntegerArgument("data_column", true)
    data_column.setDisplayName("Please enter an integer for the column from which you want to read data:")
    data_column.setDescription("(the first column is 1, the second is 2, and so on)")
    data_column.setDefaultValue(1)
    args << data_column

    # Make an argument for the rows to skip
    rows_to_skip = OpenStudio::Ruleset::OSArgument.makeIntegerArgument("rows_to_skip", true)
    rows_to_skip.setDisplayName("Please enter the number of rows to skip before the data beings:")
    # rows_to_skip.setDescription("")
    rows_to_skip.setDefaultValue(0)
    args << rows_to_skip

    # make an argument for units
    unit_choices = OpenStudio::StringVector.new
    unit_choices << 'unitless'
    unit_choices << 'C'
    unit_choices << 'W'
    unit_choices << 'm/s'
    unit_choices << 'm^3/s'
    unit_choices << 'kg/s'
    unit_choices << 'Pa'
    unit_choice = OpenStudio::Ruleset::OSArgument::makeChoiceArgument('unit_choice', unit_choices, true)
    unit_choice.setDisplayName('Choose schedule units:')
    unit_choice.setDefaultValue('unitless')
    args << unit_choice

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Need to get input saving working  
    # Need to add a flag to use Schedule:File instead of modifying the file by injecting the schedule

    # assign the user inputs to variables
    use_schedule_file   = runner.getBoolArgumentValue("use_schedule_file", user_arguments)
    replace_schedule    = runner.getBoolArgumentValue("replace_schedule", user_arguments)
    old_schedule        = runner.getOptionalWorkspaceObjectChoiceValue('old_schedule', user_arguments, model)
    new_schedule_name   = runner.getStringArgumentValue('new_schedule_name', user_arguments)
    file_dir            = runner.getOptionalStringArgumentValue('file_dir', user_arguments)
    file_name           = runner.getOptionalStringArgumentValue('file_name', user_arguments)
    data_column         = runner.getIntegerArgumentValue("data_column", user_arguments)
    rows_to_skip        = runner.getIntegerArgumentValue("rows_to_skip", user_arguments)
    unit_choice         = runner.getOptionalStringArgumentValue('unit_choice', user_arguments)

    runner.registerInfo("Path: #{file_dir}, name: #{file_name}")

    args_json_path = File.join(File.dirname(__FILE__),'../../measure_args.json')  # path to previous measure arguments save file
    if File.exist? args_json_path  

      # Check if we even need to load the json
      if file_dir.to_s == "" or file_name.to_s == ""
        runner.registerInfo("Previous arguments data exists and is being used.")
        # reads the previous arguments file if it exists
        args_json = JSON.parse(File.read(args_json_path))
        if !args_json.empty?
          runner.registerInfo("Loaded previous arguments JSON data")
        else
          runner.registerError("The JSON file exists but I can't load data from it. Is something else using it?")
          return False
        end

        # look for the file_dir and file_name argument keys in the json
        if file_dir.to_s == ""
          runner.registerInfo("Loading the directory used in a previous measure.")
          file_dir    = args_json["file_dir"]
          runner.registerInfo("Using previous directory at #{file_dir}")
        end
        if file_name.to_s == ""
          runner.registerInfo("Loading the file name used in a previous measure.")
          file_name   = args_json["file_name"]
          runner.registerInfo("Using previous file name #{file_name}")
        end
      else
        runner.registerInfo("Previous arguments data is being ignored and the provided path and name are being used.")
      end
    else
      runner.registerInfo("Creating arguments file to be used in subsequent measures")
      # if the previous arguments file doesn't exist, we'll create it
      current_arugments_hash = {
        "replace_schedule"  => replace_schedule,
        "old_schedule"      => old_schedule,
        "new_schedule_name" => new_schedule_name,
        "file_dir"          => file_dir,
        "file_name"         => file_name,
        "data_column"       => data_column,
        "rows_to_skip"      => rows_to_skip,
        "unit_choice"       => unit_choice
      }
      # write the json file
      File.open(args_json_path, "w") do |f|
        f.write(JSON.pretty_generate(current_arugments_hash))
      end
      runner.registerInfo("Saved current arguments to #{args_json_path}")
    end

    # report initial condition
    runner.registerInitialCondition("number of Existing Schedule objects = #{model.getSchedules.size}")
    
    if replace_schedule == true
      runner.registerInfo("Replacing the schedule in the model named - #{old_schedule.get.name.to_s}")
    end

    if replace_schedule != true
      # check schedule name for reasonableness
      if schedule_name == ''
        runner.registerError('Schedule name is blank. Input a schedule name or replace a schedule instead.')
        return false
      end
    end

    # # check file path for reasonableness
    # if file_path.empty?
    #   runner.registerError('Empty file path was entered.')
    #   return false
    # end

    # strip out the potential leading and trailing quotes
    # file_path.gsub!('"', '')
    # runner.registerInfo("The current working dir is #{Dir.pwd}")
    # runner.registerInfo("The file directory is #{File.dirname(__FILE__)}")
    # runner.registerInfo("The relative directory is #{File.expand_path File.dirname(__FILE__)}")
    # runner.registerInfo("Checking for OSW path #{model.workflowJSON.oswPath.get}")
    # ENV.each do |key,var|
    #   runner.registerInfo("#{key} = #{var}")
    # end

    file_path = File.join(file_dir.to_s,file_name.to_s)
    # check if file exists
    if !File.exist? file_path
      runner.registerError("The file at path #{file_path} doesn't exist.")
      return false
    else
      runner.registerInfo("Found the specified file at: #{file_path}")
    end  

    # creating our schedule
    # read in specific column of csv values while skipping specified rows
    csv_values = []
    CSV.foreach(file_path,{headers: false, converters: :float}).with_index(1) do |row, line|
      if line > rows_to_skip
        csv_values << row[data_column-1]
      end
    end
    num_rows = csv_values.length
    runner.registerInfo("Found #{num_rows} rows in the CSV file.")

    # infer interval
    interval = []
    if (num_rows == 8760) || (num_rows == 8784) # hourly data
      interval = OpenStudio::Time.new(0, 1, 0)
      minutes_per_item = 60
    elsif (num_rows == 35040) || (num_rows == 35136) # 15 min interval data
      interval = OpenStudio::Time.new(0, 0, 15)
      minutes_per_item = 15
    elsif (num_rows == 105120) || (num_rows == 105408) # 5 min interval data
      interval = OpenStudio::Time.new(0, 0, 5)
      minutes_per_item = 5
    elsif (num_rows == 525600) || (num_rows == 527040) # 1 min interval data
      interval = OpenStudio::Time.new(0, 0, 1)
      minutes_per_item = 1
    else
      runner.registerError('This measure does not support non-hourly, non-15 min, non-5 min, or non-1 min interval data.  Cast your values as 1-min (525,600 rows), 5-min (105,120 rows), 15-min (35,040 rows), or hourly (8,760 rows) interval data.  See the values template.')
      return false
    end

    if use_schedule_file == true
      runner.registerInfo("Attempting to apply ScheduleFile using the CSV data")
      external_file = OpenStudio::Model::ExternalFile.getExternalFile(model,file_path)
      if external_file.is_initialized
        external_file = external_file.get
      else
        runner.registerError("Could not find the external file to use with ScheduleFile")
        return false
      end

      # new_schedule = OpenStudio::Model::ScheduleFile.new(external_file) # ,data_column.to_int,rows_to_skip.to_int)
      new_schedule = OpenStudio::Model::ScheduleFile.new(model,file_path,data_column,rows_to_skip)
      # new_schedule.setColumnNumber(data_column)
      # new_schedule.setRowstoSkipatTop(rows_to_skip)
      # runner.registerInfo("Default Minutes per item: #{new_schedule.minutesperItem}")
      new_schedule.setMinutesperItem(minutes_per_item)
    else
      # create values for the timeseries
      schedule_values = OpenStudio::Vector.new(num_rows, 0.0)
      csv_values.each_with_index do |csv_value,i|
        schedule_values[i] = csv_value
      end

      # make a schedule
      startDate = OpenStudio::Date.new(OpenStudio::MonthOfYear.new(1), 1)
      timeseries = OpenStudio::TimeSeries.new(startDate, interval, schedule_values, "#{unit_choice}")
      new_schedule = OpenStudio::Model::ScheduleInterval::fromTimeSeries(timeseries, model)
      new_schedule = new_schedule.get # Not sure why I need a get for ScheduleInterval but not ScheduleFile -_-
      if new_schedule.empty?
        runner.registerError("Unable to make schedule from file at '#{file_path}'")
        return false
      end
    end


    num_rep_schs = 0
    if replace_schedule == true
      if new_schedule_name != ""
        runner.registerInfo("Creating a new schedule for the model named: #{new_schedule_name}")
        new_schedule.setName(new_schedule_name)
      else
        old_schedule = old_schedule.get
        new_schedule_name = "#{old_schedule.name}_interval"
        new_schedule.setName(new_schedule_name)
        runner.registerInfo("Using old schedule name to name new schedule: #{new_schedule_name}")
      end

      runner.registerInfo("Replacing the schedule from the model named: #{old_schedule.get.name.to_s}") ####### Added: .get
      sources = old_schedule.get.sources # Grab everything referencing the schedule   ####### Added: .get
      # Iterate each sources
      sources.each do |s|
        # Figure out how many fields there are to loop through them
        num_fields = s.numFields
        # loop through each field using range
        (0..num_fields-1).each do |i|
          # Actually inspect a field
          f = s.getField(i)
          if f.to_s == old_schedule.get.handle.to_s  ####### Added: .get
            s.setPointer(i,new_schedule.handle())
            runner.registerInfo("Updated an occurance of the old schedule in #{s.name}")
            num_rep_schs += 1
          end
        end
      end
    else
      if new_schedule_name != ""
        runner.registerInfo("Creating a new schedule for the model named: #{new_schedule_name}")
        new_schedule = new_schedule.get
        new_schedule.setName(new_schedule_name)
      else
        runner.registerError("Please enter a name for the schedule or choose to replace a schedule instead")
      end
    end

    # reporting final condition of model
    runner.registerFinalCondition("Added schedule #{new_schedule_name} to the model. Updated #{num_rep_schs} existing schedule pointers.")

    return true
  end
end

# this allows the measure to be use by the application
AddAndApplyIntervalScheduleFromFile.new.registerWithApplication