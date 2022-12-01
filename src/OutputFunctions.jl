function 完整輸出(data, sup_data, data_folder, data_name)
    create_order_start_time!(sup_data) #建立工單開始時間查詢表
    retag_order!(data, sup_data) #重新tag工單 紅/綠
    output_json(sup_data, data_folder,"$data_name") #Gantt.json
    儲存排程報表資料(data, sup_data, "$(data_folder)", "$(data_name)排程報表") #排程細節報表
    fit_dict = cal_fit_without_norm(sup_data["sol"], data) 
    set_min_max_dict!(data, fit_dict) #設定上下限(For normalization)
    init_result = cal_fit(sup_data["sol"], data) # 初始解結果
    path = pwd()*"/Output/ScheduleResults/$data_folder/Performance.csv"
    output_date = data_folder[1:4]*"/"*data_folder[5:6]*"/"*data_folder[7:8]
    init_result = results_transform!(init_result, output_date, data_name)
    produce_row(path, init_result)
end
function create_order_start_time!(sup_data)
    schedule = sup_data["schedule"]
    order_start_dict = Dict()
    for (rs_id, rs) in schedule.rs_dict
        interval_list = get_interval_list(rs)
        for interval in interval_list
            if interval isa Block
                start = get!(order_start_dict, interval.attributes.name, typemax(Int))
                interval_start = get_start(interval)
                if get_start(interval) < start 
                    order_start_dict[interval.attributes.name] = interval_start
                end
            end
        end
    end
    sup_data["order_start_dict"] = order_start_dict
end
#根據新排程的工單，重新調整tag 紅單、綠單。 #TODO: 確認是否需要重新標註綠單
function retag_order!(data, sup_data)
    order_start_dict = sup_data["order_start_dict"]
    WO = data["sup_data"]["WO"]
    for (order_id, order_start) in order_start_dict
        if order_start <= 24*3600 #一天內 紅色工單
            if haskey(data["sup_data"]["WO"], order_id) #若WO有 (只需要確認WO的 因為只有WO的是Green的)
                order = data["sup_data"]["WO"][order_id]
                order.info["color"] = "red"
            end
        end
    end
end
function output_json(sup_data, folder_name, name)
    schedule = sup_data["schedule"]
    trans(interval) = Dict("name" => IntervalMod.get_name(interval),
                           "start" => get_start(interval),
                           "finish" => get_finish(interval),
                           "is_delay" =>interval.attributes.info["is_delay"],
                           "key"=>IntervalMod.get_key(interval)
                        )
    new_schedule = Dict()
    new_schedule["version"] = schedule.version
    new_schedule["CURRENTTIME"] = schedule.CURRENTTIME
    new_schedule["results"] = Dict()
    
    for (rs_id, rs) in schedule.rs_dict
        interval_list = get_interval_list(rs)
            # clean_dummy!(interval_list)

        new_interval_list = get!(new_schedule["results"], rs_id, [])
        for interval in interval_list
            
            if typeof(interval) <: Dummy || typeof(interval) <: Forbidden
                continue
            else
                order = sup_data["interval_dict"][IntervalMod.get_key(interval)]["order"]
                if haskey(sup_data["wip_orders"], order.id)
                    order = sup_data["wip_orders"][order.id]
                elseif haskey(sup_data["WO"], order.id)
                    order = sup_data["WO"][order.id]
                end
                @show order.info["DD"]
                if get_finish(interval)> order.info["DD"]
                 
                    interval.attributes.info["is_delay"] = true
                else
                    interval.attributes.info["is_delay"] = false
                end
                    push!(new_interval_list, trans(interval))
            end
        end
    end
    return save_json(new_schedule, folder_name, name)
end
function screen_shot2(file, output_path, name)
    jDict1 = JSON.json(file)
    f = open(output_path, "w")
    JSON.print(f, jDict1)
    close(f)
end
function save_json(file, folder_name, file_name)
    println("儲存$(file_name)甘特圖資料中...")
    dir = "./Output/ScheduleResults/$folder_name"
    if !isdir(dir)
        mkdir(dir)
    end
    @show dir
    # screen_shot2(file, "./APS/Output/OutputData/$file_name.json", file_name)
    #儲存至資料夾
    # dir = "./Output/OutputData/新資料夾/$folder_name"
    # if isdir(dir) || mkdir(dir)
        
    # end
    screen_shot2(file, dir*"//$file_name.json", file_name)
end
function reorder_run_seq(row_list)
    #run seq 要by resource 還有開始時間重新覆寫
    
    rs_data_list_dict =  Dict()
    for row in row_list
        rs_name = row["OPR_RESOURCE_NAME"]
        rs_data_list = get!(rs_data_list_dict, rs_name, [])
        push!(rs_data_list, row)
    end
    #重新排序
    for (k, data_list) in rs_data_list_dict
        sort!(data_list, by=x->x["OPR_START_DATE"])
    end
    order_seq_record = Dict()
    #給seq 
    for (k, data_list) in rs_data_list_dict
        for (idx, row) in enumerate(data_list)
            if haskey(order_seq_record, row["WIP_ENTITY_NAME"])
                row["RUN_SEQ"] = order_seq_record[row["WIP_ENTITY_NAME"]]
            else
                order_seq_record[row["WIP_ENTITY_NAME"]] = idx
                row["RUN_SEQ"] = idx
     
            end
        end
    end
    row_list = []
    for (k, data_list) in rs_data_list_dict
        for (idx, row) in enumerate(data_list)
            push!(row_list, row)
        end
    end
    return row_list
end
function 儲存排程報表資料(data, sup_data, file_name, type)
  row_list = output_table(data, sup_data)
  # 重新按照start_time調整run_seq順序
  row_list = reorder_run_seq(row_list)
  df = DataFrame(ORGANIZATION_CODE=String[],
                OPR_RESOURCE_NAME=String[],
                APS_INFO = String[],
                RUN_SEQ=Int[],
                OPR_SEQ_NUM=String[],
                ITEM_NAME=String[],
                WIP_ENTITY_ID=Float64[],
                WIP_ENTITY_NAME=String[],
                BATCH_NUM=Float64[],
                START_QTY=Float64[],
                OPR_START_QTY=Float64[],
                OPR_COMPLETION_QTY=Float64[],
                OPR_POH=Float64[],
                CHANGEOVER_HOURS=Float64[],
                DURA_HOURS=Float64[],
                SETUP_START_DATE=String[],
                OPR_START_DATE=String[],
                OPR_END_DATE=String[],
                REQUEST_JOB = String[],
                SHIP_DATE = String[],
                PRIORITY = Float64[],
                IS_SCHEDULE_ORDER = Bool[],
                MATERIAL_CONSTRAINT_REASON= String[],
                MATERIAL_CONSTRAINT_TIME=String[],
                OPR_CONSTRAINT_REASON =String[],
                OPR_CONSTRAINT_TIME =String[],
                STENCIL_CONSTRAINT_REASON= String[],
                STENCIL_CONSTRAINT_TIME=String[],
                MACHINE_COMPLETION_CONSTRAINT_REASON= String[],
                MACHINE_COMPLETION_CONSTRAINT_TIME=String[],
                ORDER_START_CONSTRAINT_REASON= String[],
                ORDER_START_CONSTRAINT_TIME=String[],
                DELAY_REASON = String[],
                TARDINESS = Float64[]
                )
  for row in row_list
      push!(df, row)
  end
#@show dirname(pwd())
  CSV.write(pwd()*"/Output/ScheduleResults/$(file_name)/$type.csv", df)
  println("$(file_name)資料儲存成功")
end
