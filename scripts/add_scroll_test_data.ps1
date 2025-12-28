
$Url = "http://localhost:5203/api/components"

echo "Injecting LARGE Mock Data (Scroll Test)..."

$system = "ScrollTestSystem"
$project = "WideTableProject"
$now = Get-Date

# Create 50 items to ensure vertical scroll
for ($i = 1; $i -le 50; $i++) {
    
    # Create payload with MANY properties to ensure horizontal scroll
    $payload = [Ordered]@{
        Name                      = "Scroll_Item_$i"
        Severity                  = "ok"
        Message                   = "Row $i for scroll testing"
        Prop_A_Long_Column_Name   = "Value_A_$i"
        Prop_B_Detailed_Info      = "Some detailed info for B $i"
        Prop_C_More_Details       = "More stuff here C $i"
        Prop_D_Extra_Data         = "Extra D $i"
        Prop_E_Configuration      = "Config E $i"
        Prop_F_Status_Detail      = "Status F $i"
        Prop_G_Region_Zone        = "Zone G $i"
        Prop_H_Architecture       = "Arch H $i"
        Prop_I_Responsibility     = "Team I $i"
        Prop_J_Last_Updated       = "Update J $i"
        Prop_K_Version_Control    = "v1.0.$i"
        Prop_L_Dependency_Map     = "Dep L $i"
        Prop_M_Audit_Trail        = "Audit M $i"
        Prop_N_Security_Level     = "Sec N $i"
        Prop_O_Performance_Metric = "Perf O $i"
    }

    $body = @{
        systemName  = $system
        projectName = $project
        payload     = $payload | ConvertTo-Json
    }

    try {
        $response = Invoke-RestMethod -Uri $Url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop
        Write-Host "Posted: Item $i"
    }
    catch {
        Write-Host "Error posting item $i : $_" -ForegroundColor Red
    }
}

echo "Done! Check '$system - $project' in dashboard."
