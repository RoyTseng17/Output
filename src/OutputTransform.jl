function add_unfinished_order(data)
    #在將其他工單加入row list之前 就將未結工單集合加入
    other_order_op_interval_tuple_list = create_other_order_op_interval_tuple_list(data)
    rs_job_counter_dict = Dict()
    match_dict = Dict("L_SMT060" => "60", "L_SMT070" => "70", "L_SMT080" => "80", "L_SMT090" => "90")
    row_list = []
    for (op, interval) in other_order_op_interval_tuple_list
        rs_id = op.info["OPR_RESOURCE_CODE"]
        if haskey(rs_job_counter_dict, rs_id)
            rs_job_counter_dict[rs_id] += 1
        else
            rs_job_counter_dict[rs_id] = 1
        end
        op.info["priority"] = 0
        op.info["score"] = 0
        op.info["new_request_job"] = ""
        row_data = 調整row_data資料(op, interval, match_dict[rs_id], rs_job_counter_dict[rs_id], data["CURRENTTIME"], false)
        row_data["APS_INFO"] = ""
        push!(row_list, row_data)
    end 
    #並將每條線的最後一筆時間紀錄，之後加入的第一筆工單，必須要是那個時間點+1秒之後
    sort!(row_list, by=x->x["OPR_START_DATE"])
    return row_list
end
function create_other_order_op_interval_tuple_list(data)
    other_order_dict = data["other_order_dict"]
    other_order_op_interval_tuple_list = []
    for (order_id, order) in other_order_dict
        for op in order.op_list
            start = Dates.DateTime(op.info["OPR_START_DATE"], DateFormat("yyyy-mm-dd HH:MM:SS"))
            start = Dates.datetime2unix(start) - data["CURRENTTIME"]
            interval = WOBlock(IntervalDetails("Dummy", "Dummy", IntervalMod.Time(Dict("start" => start, "finish"=>start+1))))
            push!(other_order_op_interval_tuple_list, (op, interval))
        end
    end
    return other_order_op_interval_tuple_list
end
# other_order_dict = data["other_order_dict"]
# other_order_op_interval_tuple_list = create_other_order_op_interval_tuple_list(data)
function output_table(data, sup_data)
    schedule = sup_data["schedule"]
    interval_dict = sup_data["interval_dict"]
    material_ES = data["sup_data"]["material_ES"]
    CURRENTTIME_stamp = data["CURRENTTIME"]
    material_info_string = build_material_info_string(CURRENTTIME_stamp, data["sup_data"]["material_info"])
    WO = sup_data["WO"]
    dispatched_order = nothing
    
    row_list = add_unfinished_order(data)
    for (rs_id, rs) in schedule.rs_dict
        job_counter = 1
        for (idx, interval) in enumerate(get_interval_list(rs))
            if interval isa Block
                # @show IntervalMod.get_key(interval)
                order = interval_dict[IntervalMod.get_key(interval)]["order"]
                try
                    dispatched_order = WO[order.id]
                catch e 
                    dispatched_order = sup_data["wip_orders"][order.id]
                end
                dispatched_op = dispatched_order.op_list[1] #BondedOperation, QualityOperation...
                op = interval_dict[IntervalMod.get_key(interval)]["op"]
                op.info["priority"] = dispatched_op.info["priority"]
                op.info["score"] = dispatched_op.info["score"]
                
                if haskey(sup_data["WO"], order.id)
                    scheduled_order = sup_data["WO"][order.id]
                    op.info["new_request_job"] = haskey(scheduled_order.info, "new_request_job") ? scheduled_order.info["new_request_job"] : ""
                elseif haskey(sup_data["wip_orders"], order.id)
                    scheduled_order = sup_data["wip_orders"][order.id]
                    op.info["new_request_job"] = haskey(scheduled_order.info, "new_request_job") ? scheduled_order.info["new_request_job"] : ""
                else
                    op.info["new_request_job"] = haskey(op.info, "new_request_job") ? op.info["new_request_job"] : ""
                end
                
               
                row_data = 調整row_data資料(op, interval, rs_id, job_counter, CURRENTTIME_stamp, true)
                
                if haskey(material_info_string, order.id)
                    #string builder
                    row_data["APS_INFO"] = material_info_string[order.id]
                    delete!(material_info_string, order.id)
                else
                    row_data["APS_INFO"] = ""
                end
                push!(row_list, row_data)
                job_counter+=1
            end
        end
    end
    return row_list
end

function create_table(result, path)
    df = DataFrame(Date = String[],
                  VERSION = String[],
                  TOTAL_CHANGEOVER_TIME = Float64[],
                  MAKESPAN = Float64[],
                  UTILITY = Float64[],
                  TOTAL_TD = Float64[],
                  ONE_DAY_TARDY = Float64[],
                  THREE_DAY_TARDY = Float64[],
                  OBJECTIVE_VALUE = Float64[]
                  )
      dummy = Dict(:Date=>"2021/01/01",
                   :VERSION=>"Dummy",
                   :ONE_DAY_TARDY => 0,
                   :THREE_DAY_TARDY => 0, 
                   :OBJECTIVE_VALUE => Float64(0),
                   :TOTAL_TD => Float64(0),
                   :MAKESPAN => Float64(0), 
                   :UTILITY => Float64(0),
                   :TOTAL_CHANGEOVER_TIME =>Float64(0)
                   )
  
      push!(df, dummy)
      CSV.write(path, df)
  end
  
  function produce_row(path, result)
    csv = nothing
    try
      csv = CSV.File(path, types=Dict(:Date=>String,
                    :VERSION=>String,
                    :TOTAL_CHANGEOVER_TIME=> Float64,
                    :MAKESPAN=>Float64,
                    :UTILITY=>Float64,
                    :TOTAL_TD=> Float64,
                    :ONE_DAY_TARDY=>Float64,
                    :THREE_DAY_TARDY=>Float64,
                    :OBJECTIVE_VALUE=>Float64,
                    ))
    catch e 
       create_table(result, path)
       csv = CSV.File(path, types=Dict(:Date=>String,
                    :VERSION=>String,
                    :TOTAL_CHANGEOVER_TIME=> Float64,
                    :MAKESPAN=>Float64,
                    :UTILITY=>Float64,
                    :TOTAL_TD=> Float64,
                    :ONE_DAY_TARDY=>Float64,
                    :THREE_DAY_TARDY=>Float64,
                    :OBJECTIVE_VALUE=>Float64,
                    ))
    end
   
    df = DataFrame(csv)
    push!(df, result)
    CSV.write(path, df)
  end
  function build_material_info_string(CURRENTTIME_stamp, material_info)
    material_info_string = Dict()
    for (order_id, order_material_list) in material_info
        output_string = ""
        sort!(order_material_list, by=x -> length(x[3]), rev=true) #sort by source string lenght
        for material_info in order_material_list
            if material_info == ("Dummy", 0, "")
                material_info_string[order_id] = ""
                break
            end
            output_string *= material_info[3] == "" ? "" : material_info[3]
            output_string *= material_info[3] == "" ? "material:" * material_info[1] : " material" * material_info[1]
            output_string *= " " * get_date(CURRENTTIME_stamp, material_info[2]) * "\n"

        end
        material_info_string[order_id] = output_string
    end
    return material_info_string
end
function get_date(CURRENTTIME_stamp, time)
    new_time = CURRENTTIME_stamp + time
    new_date = unix2datetime(new_time)
    new_date = Dates.format(new_date, "yyyy-mm-dd HH:MM:SS")
    return new_date
end
function 調整row_data資料(op, interval, rs_id, idx, CURRENTTIME_stamp, is_schedule_order)
    rs_name = Dict("60" => "L_SMT060",
        "70" => "L_SMT070",
        "80" => "L_SMT080",
        "90" => "L_SMT090"
    )
    row_data = Dict("ORGANIZATION_CODE" => op.info["ORGANIZATION_CODE"],
        "OPR_RESOURCE_NAME" => rs_name[rs_id],
        "RUN_SEQ" => idx,
        "OPR_SEQ_NUM" => op.info["op_id"],
        "ITEM_NAME" => op.info["pd_id"],
        "WIP_ENTITY_NAME" => op.info["order_id"],
        "WIP_ENTITY_ID" => op.info["WIP_ENTITY_ID"],
        "START_QTY" => op.info["start_qty"],
        "OPR_START_QTY" => op.info["start_qty"],
        "OPR_COMPLETION_QTY" => op.info["completion_qty"],
        "OPR_POH" => op.info["OPR_POH"],
        "CHANGEOVER_HOURS" => get_setup_time(interval) / 3600,
        "DURA_HOURS" => get_duration(interval) / 3600,
        "SETUP_START_DATE" => get_date(CURRENTTIME_stamp, get_start(interval)),
        "OPR_START_DATE" => get_date(CURRENTTIME_stamp, (get_start(interval) + get_setup_time(interval))),
        "OPR_END_DATE" => get_date(CURRENTTIME_stamp, get_finish(interval)),
        "REQUEST_JOB" => op.info["new_request_job"] === missing ? "" : op.info["new_request_job"],
        "SHIP_DATE" => op.info["SHIP_DATE"],
        "PRIORITY" => op.info["priority"],
        "BATCH_NUM" => op.info["batch_num"],
        "IS_SCHEDULE_ORDER"=>is_schedule_order
    )
    #"SHIP_DATE2"=>get_date(CURRENTTIME_stamp, op.info["DD"]),
    constraint_ES_dict = get!(interval.attributes.info, "constraint_ES_dict", Dict())

    col_dict = Dict("物料限制" => ["MATERIAL_CONSTRAINT_REASON", "MATERIAL_CONSTRAINT_TIME"],
        "工序限制" => ["OPR_CONSTRAINT_REASON", "OPR_CONSTRAINT_TIME"],
        "鋼板限制" => ["STENCIL_CONSTRAINT_REASON", "STENCIL_CONSTRAINT_TIME"],
        "機台完工時間限制" => ["MACHINE_COMPLETION_CONSTRAINT_REASON", "MACHINE_COMPLETION_CONSTRAINT_TIME"],
        "工單可開始時間限制" => ["ORDER_START_CONSTRAINT_REASON", "ORDER_START_CONSTRAINT_TIME"])
    
    for (k, v) in col_dict
        if haskey(constraint_ES_dict, k)
            row_data[v[1]] = constraint_ES_dict[k][1]
            row_data[v[2]] = get_date(CURRENTTIME_stamp, constraint_ES_dict[k][2])
        else
            row_data[v[1]] = ""
            row_data[v[2]] = ""
        end
    end
    if !row_data["IS_SCHEDULE_ORDER"]
        row_data["DELAY_REASON"] = ""
        row_data["TARDINESS"] = 0
        row_data["STENCIL_CONSTRAINT_REASON"] = ""
        return row_data
    end
    constraint_ES_list = collect(constraint_ES_dict)
    first_value = constraint_ES_list[1][2][2]
    all_equal = true
    for (key, constraint_ES) in constraint_ES_list
        if constraint_ES[2] > 0 && constraint_ES[2] != first_value
            all_equal = false
            break
        end
    end
    if all_equal
        row_data["DELAY_REASON"] = ""
    else
        row_data["DELAY_REASON"] = sort(collect(constraint_ES_dict), by=x -> -x[2][2])[1][1]
    end
    if op.info["last_op"]
        row_data["TARDINESS"] = (get_finish(interval) - op.info["DD"]) > 0 ? (get_finish(interval) - op.info["DD"]) : 0
    else
        row_data["TARDINESS"] = 0
    end
    row_data["STENCIL_CONSTRAINT_REASON"] = string(row_data["STENCIL_CONSTRAINT_REASON"])
    return row_data
end
function results_transform!(result, date2, version)
    result["mksp"] /= 3600
    result["total_changeover_time"] /= 3600
    # 
    result = Dict(:Date => date2,
        :ONE_DAY_TARDY => result["one_day_NTD"],
        :THREE_DAY_TARDY => result["three_day_NTD"],
        :OBJECTIVE_VALUE => round(result["fitness"], digits=3),
        :UTILITY => result["avg_utilization"],
        :MAKESPAN => result["mksp"],
        :TOTAL_CHANGEOVER_TIME => result["total_changeover_time"],
        :VERSION => version,
        :TOTAL_TD => result["total_TD"],
    )
    return result
end
