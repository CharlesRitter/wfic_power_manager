    <#
    Charles R Ritter III (crritte)
    4/20/2018
    Watt Family Innovation Center
    ******************************
    Reads in a list of computers from a text file and either resets, powers off, or powers on those computers using Intel AMT
    AMT must be enabled on those computers in order for this script to work (See [REDACTED] scripts starting with [REDACTED] for instructions)
    #>

Import-Module IntelvPro
$operation = $args[0] #the operation to be performed
$compFile = $args[1] #the file containing the list of computers

if($args.length -ne 2 -or ( ($operation -ne "PowerOn") -and ($operation -ne "PowerOff") -and ($operation -ne "Reset") ) ){
    #Do nothing if the script was called incorrectly
    Write-Host "Invalid Arguments. Proper Usage: .\wfic-power_manager.ps1 [PowerOn or PowerOff or Reset] [FILENAME in ""quotes""]"
} else {
    $endState #the Power State ID that the each computer should reach by the end of the script
    if($operation -eq "PowerOn") {$endState = 2}
    if($operation -eq "PowerOff") {$endState = 8}

    $amtComputers = @(Get-Content $compFile) #Reads in the list of computers into an array

    #### The valid parameters for –Operation are {PowerOn, PowerOff, Reset}

    #loop that detects all of the computers that I can't connect to
    foreach($pc in $amtComputers){
        $validPC = $pc | Get-AMTPowerState -Username:"[REDACTED]" -Password:"[REDACTED]" #variable to check if we can connect to the computer

        #remove the computers we can't connect to and print an error
        if($validPC.'Power State Description' -eq "Cannot connect") {
            $amtComputers = $amtComputers | Where-Object {$_ -ne $pc}
            Write-Host ($pc + " FAILED: Cannot Connect")
        }
    }


    #Starts a background job which executes Invoke-AMTPowerManagement on each computer
    #The process can take a long time and starting several background jobs is the only way I have found to execute them simultaneously, otherwise
    #the loop will wait for the current command to finish before moving on to the next computer
    foreach($pc in $amtComputers){
        Start-Job -ScriptBlock{$args[0] | Invoke-AMTPowerManagement -Operation:$args[1] -Username:"[REDACTED]" -Password:"[REDACTED]"} -ArgumentList($pc, $operation) -Name $pc
    }

    #Waits for all the jobs to finish and then removes them
    #Since AMT works somewhat inconsistently, I have the script check to see if the job completed successfully before ending and restart the job if it didn't
    $success #have all jobs completed successfully
    do{
        $success = $true

        foreach($pc in $amtComputers){
            $powerState = $pc | Get-AMTPowerState -Username:"[REDACTED]" -Password:"[REDACTED]" #the power state of the computer

            #is the computer in the desired power state and, if not, has the job for that computer completed?
            if( ($powerState.'Power State ID' -ne $endState) -or (Get-Job -Name $pc).State -ne "Completed"){
                $success = $false

                #if the job has completed, start a new job until the computer reaches the ending state
                if((Get-Job -Name $pc).State -eq "Completed"){
                    Get-Job -Name $pc | Remove-Job
                    Start-Job -ScriptBlock{$args[0] | Invoke-AMTPowerManagement -Operation:$args[1] -Username:"[REDACTED]" -Password:"[REDACTED]"} -ArgumentList($pc, $operation) -Name $pc
                }
            }
        }
    }while($success -eq $false)#compares the number of completed jobs to the number of started jobs

    Get-Job | Remove-Job #removes all the jobs
}