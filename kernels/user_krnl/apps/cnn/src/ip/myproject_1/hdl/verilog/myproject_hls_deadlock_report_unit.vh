   
    parameter PROC_NUM = 17;
    parameter ST_IDLE = 2'b0;
    parameter ST_DL_DETECTED = 2'b1;
    parameter ST_DL_REPORT = 2'b10;
   

    reg find_df_deadlock = 0;
    reg [1:0] CS_fsm;
    reg [1:0] NS_fsm;
    reg [PROC_NUM - 1:0] dl_detect_reg;
    reg [PROC_NUM - 1:0] dl_done_reg;
    reg [PROC_NUM - 1:0] origin_reg;
    reg [PROC_NUM - 1:0] dl_in_vec_reg;
    integer i;
    integer fp;

    // FSM State machine
    always @ (negedge reset or posedge clock) begin
        if (~reset) begin
            CS_fsm <= ST_IDLE;
        end
        else begin
            CS_fsm <= NS_fsm;
        end
    end
    always @ (CS_fsm or dl_in_vec or dl_detect_reg or dl_done_reg or dl_in_vec or origin_reg) begin
        NS_fsm = CS_fsm;
        case (CS_fsm)
            ST_IDLE : begin
                if (|dl_in_vec) begin
                    NS_fsm = ST_DL_DETECTED;
                end
            end
            ST_DL_DETECTED: begin
                // has unreported deadlock cycle
                if (dl_detect_reg != dl_done_reg) begin
                    NS_fsm = ST_DL_REPORT;
                end
            end
            ST_DL_REPORT: begin
                if (|(dl_in_vec & origin_reg)) begin
                    NS_fsm = ST_DL_DETECTED;
                end
            end
        endcase
    end

    // dl_detect_reg record the procs that first detect deadlock
    always @ (negedge reset or posedge clock) begin
        if (~reset) begin
            dl_detect_reg <= 'b0;
        end
        else begin
            if (CS_fsm == ST_IDLE) begin
                dl_detect_reg <= dl_in_vec;
            end
        end
    end

    // dl_detect_out keeps in high after deadlock detected
    assign dl_detect_out = |dl_detect_reg;

    // dl_done_reg record the cycles has been reported
    always @ (negedge reset or posedge clock) begin
        if (~reset) begin
            dl_done_reg <= 'b0;
        end
        else begin
            if ((CS_fsm == ST_DL_REPORT) && (|(dl_in_vec & dl_detect_reg) == 'b1)) begin
                dl_done_reg <= dl_done_reg | dl_in_vec;
            end
        end
    end

    // clear token once a cycle is done
    assign token_clear = (CS_fsm == ST_DL_REPORT) ? ((|(dl_in_vec & origin_reg)) ? 'b1 : 'b0) : 'b0;

    // origin_reg record the current cycle start id
    always @ (negedge reset or posedge clock) begin
        if (~reset) begin
            origin_reg <= 'b0;
        end
        else begin
            if (CS_fsm == ST_DL_DETECTED) begin
                origin_reg <= origin;
            end
        end
    end
   
    // origin will be valid for only one cycle
    always @ (CS_fsm or dl_detect_reg or dl_done_reg) begin
        if (CS_fsm == ST_DL_DETECTED) begin
            for (i = 0; i < PROC_NUM; i = i + 1) begin
                if (dl_detect_reg[i] & ~dl_done_reg[i] & ~(|origin)) begin
                    origin = 'b1 << i;
                end
            end
        end
        else begin
            origin = 'b0;
        end
    end
    
    // dl_in_vec_reg record the current cycle dl_in_vec
    always @ (negedge reset or posedge clock) begin
        if (~reset) begin
            dl_in_vec_reg <= 'b0;
        end
        else begin
            if (CS_fsm == ST_DL_DETECTED) begin
                dl_in_vec_reg <= origin;
            end
            else if (CS_fsm == ST_DL_REPORT) begin
                dl_in_vec_reg <= dl_in_vec;
            end
        end
    end
    
    // get the first valid proc index in dl vector
    function integer proc_index(input [PROC_NUM - 1:0] dl_vec);
        begin
            proc_index = 0;
            for (i = 0; i < PROC_NUM; i = i + 1) begin
                if (dl_vec[i]) begin
                    proc_index = i;
                end
            end
        end
    endfunction

    // get the proc path based on dl vector
    function [768:0] proc_path(input [PROC_NUM - 1:0] dl_vec);
        integer index;
        begin
            index = proc_index(dl_vec);
            case (index)
                0 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0";
                end
                1 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0";
                end
                2 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0";
                end
                3 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0";
                end
                4 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0";
                end
                5 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0";
                end
                6 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0";
                end
                7 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0";
                end
                8 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0";
                end
                9 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0";
                end
                10 : begin
                    proc_path = "myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0";
                end
                11 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0";
                end
                12 : begin
                    proc_path = "myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0";
                end
                13 : begin
                    proc_path = "myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0";
                end
                14 : begin
                    proc_path = "myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0";
                end
                15 : begin
                    proc_path = "myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0";
                end
                16 : begin
                    proc_path = "myproject_myproject.softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0";
                end
                default : begin
                    proc_path = "unknown";
                end
            endcase
        end
    endfunction

    // print the headlines of deadlock detection
    task print_dl_head;
        begin
            $display("\n//////////////////////////////////////////////////////////////////////////////");
            $display("// ERROR!!! DEADLOCK DETECTED at %0t ns! SIMULATION WILL BE STOPPED! //", $time);
            $display("//////////////////////////////////////////////////////////////////////////////");
            fp = $fopen("deadlock_db.dat", "w");
        end
    endtask

    // print the start of a cycle
    task print_cycle_start(input reg [768:0] proc_path, input integer cycle_id);
        begin
            $display("/////////////////////////");
            $display("// Dependence cycle %0d:", cycle_id);
            $display("// (1): Process: %0s", proc_path);
            $fdisplay(fp, "Dependence_Cycle_ID %0d", cycle_id);
            $fdisplay(fp, "Dependence_Process_ID 1");
            $fdisplay(fp, "Dependence_Process_path %0s", proc_path);
        end
    endtask

    // print the end of deadlock detection
    task print_dl_end(input integer num, input integer record_time);
        begin
            $display("////////////////////////////////////////////////////////////////////////");
            $display("// Totally %0d cycles detected!", num);
            $display("////////////////////////////////////////////////////////////////////////");
            $display("// ERROR!!! DEADLOCK DETECTED at %0t ns! SIMULATION WILL BE STOPPED! //", record_time);
            $display("//////////////////////////////////////////////////////////////////////////////");
            $fdisplay(fp, "Dependence_Cycle_Number %0d", num);
            $fclose(fp);
        end
    endtask

    // print one proc component in the cycle
    task print_cycle_proc_comp(input reg [768:0] proc_path, input integer cycle_comp_id);
        begin
            $display("// (%0d): Process: %0s", cycle_comp_id, proc_path);
            $fdisplay(fp, "Dependence_Process_ID %0d", cycle_comp_id);
            $fdisplay(fp, "Dependence_Process_path %0s", proc_path);
        end
    endtask

    // print one channel component in the cycle
    task print_cycle_chan_comp(input [PROC_NUM - 1:0] dl_vec1, input [PROC_NUM - 1:0] dl_vec2);
        reg [856:0] chan_path;
        integer index1;
        integer index2;
        begin
            index1 = proc_index(dl_vec1);
            index2 = proc_index(dl_vec2);
            case (index1)
                0 : begin
                    case(index2)
                    1: begin
                        if (~conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_38_12_5_3_0_8u_config2_s_fu_143.layer2_out_blk_n) begin
                            if (~layer2_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer2_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer2_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer2_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer2_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer2_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U.if_full_n & conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0.ap_start & ~conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0.real_start & (trans_in_cnt_0 == trans_out_cnt_0) & ~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0',");
                        end
                    end
                    endcase
                end
                1 : begin
                    case(index2)
                    0: begin
                        if (~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0.data_blk_n) begin
                            if (~layer2_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer2_out_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer2_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer2_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer2_out_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer2_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U.if_empty_n & relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0.ap_idle & ~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_3u_array_ap_fixed_38_12_5_3_0_8u_config2_U0',");
                        end
                    end
                    2: begin
                        if (~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0.res_blk_n) begin
                            if (~layer5_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer5_out_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer5_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer5_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer5_out_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer5_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U.if_full_n & relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0.ap_start & ~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0.real_start & (trans_in_cnt_1 == trans_out_cnt_1) & ~start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0',");
                        end
                    end
                    endcase
                end
                2 : begin
                    case(index2)
                    1: begin
                        if (~conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0.layer5_out_blk_n) begin
                            if (~layer5_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer5_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer5_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer5_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer5_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer5_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U.if_empty_n & conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0.ap_idle & ~start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6eAS_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config5_U0',");
                        end
                    end
                    3: begin
                        if (~conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_40_14_5_3_0_16u_config6_s_fu_267.layer6_out_blk_n) begin
                            if (~layer6_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer6_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer6_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer6_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer6_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer6_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U.if_full_n & conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0.ap_start & ~conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0.real_start & (trans_in_cnt_2 == trans_out_cnt_2) & ~start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U' read by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0',");
                        end
                    end
                    endcase
                end
                3 : begin
                    case(index2)
                    2: begin
                        if (~relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0.data_blk_n) begin
                            if (~layer6_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer6_out_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer6_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer6_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer6_out_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer6_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U.if_empty_n & relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0.ap_idle & ~start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_8u_array_ap_fixed_40_14_5_3_0_16u_config6_U0',");
                        end
                    end
                    4: begin
                        if (~relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0.res_blk_n) begin
                            if (~layer9_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer9_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer9_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer9_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer9_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer9_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U.if_full_n & relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0.ap_start & ~relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0.real_start & (trans_in_cnt_3 == trans_out_cnt_3) & ~start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0',");
                        end
                    end
                    endcase
                end
                4 : begin
                    case(index2)
                    3: begin
                        if (~conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0.layer9_out_blk_n) begin
                            if (~layer9_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer9_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer9_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer9_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer9_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer9_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U.if_empty_n & conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0.ap_idle & ~start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0_U' written by process 'myproject_myproject.relu_array_ap_fixed_16u_array_ap_fixed_16_3_5_3_0_16u_relu_config9_U0',");
                        end
                    end
                    5: begin
                        if (~conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_41_15_5_3_0_32u_config10_s_fu_473.layer10_out_blk_n) begin
                            if (~layer10_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer10_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer10_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer10_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer10_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer10_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U.if_full_n & conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0.ap_start & ~conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0.real_start & (trans_in_cnt_4 == trans_out_cnt_4) & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0',");
                        end
                    end
                    endcase
                end
                5 : begin
                    case(index2)
                    4: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0.data_blk_n) begin
                            if (~layer10_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer10_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer10_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer10_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer10_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer10_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U.if_empty_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0.ap_idle & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13eBS_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_41_15_5_3_0_32u_config10_U0',");
                        end
                    end
                    6: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0.res_blk_n) begin
                            if (~layer13_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer13_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer13_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer13_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer13_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer13_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U.if_full_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0.ap_start & ~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0.real_start & (trans_in_cnt_5 == trans_out_cnt_5) & ~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0',");
                        end
                    end
                    endcase
                end
                6 : begin
                    case(index2)
                    5: begin
                        if (~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0.layer13_out_blk_n) begin
                            if (~layer13_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer13_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer13_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer13_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer13_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer13_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U.if_empty_n & conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0.ap_idle & ~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config13_U0',");
                        end
                    end
                    7: begin
                        if (~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_42_16_5_3_0_32u_config14_s_fu_889.layer14_out_blk_n) begin
                            if (~layer14_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer14_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer14_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer14_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer14_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer14_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U.if_full_n & conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0.ap_start & ~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0.real_start & (trans_in_cnt_6 == trans_out_cnt_6) & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0',");
                        end
                    end
                    endcase
                end
                7 : begin
                    case(index2)
                    6: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0.data_blk_n) begin
                            if (~layer14_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer14_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer14_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer14_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer14_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer14_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U.if_empty_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0.ap_idle & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17eCS_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config14_U0',");
                        end
                    end
                    8: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0.res_blk_n) begin
                            if (~layer17_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer17_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer17_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer17_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer17_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer17_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U.if_full_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0.ap_start & ~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0.real_start & (trans_in_cnt_7 == trans_out_cnt_7) & ~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0',");
                        end
                    end
                    endcase
                end
                8 : begin
                    case(index2)
                    7: begin
                        if (~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0.layer17_out_blk_n) begin
                            if (~layer17_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer17_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer17_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer17_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer17_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer17_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U.if_empty_n & conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0.ap_idle & ~start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config17_U0',");
                        end
                    end
                    9: begin
                        if (~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_42_16_5_3_0_32u_config18_s_fu_889.layer18_out_blk_n) begin
                            if (~layer18_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer18_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer18_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer18_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer18_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer18_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U.if_full_n & conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0.ap_start & ~conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0.real_start & (trans_in_cnt_8 == trans_out_cnt_8) & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0',");
                        end
                    end
                    endcase
                end
                9 : begin
                    case(index2)
                    8: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0.data_blk_n) begin
                            if (~layer18_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer18_out_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer18_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer18_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer18_out_U' read by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer18_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U.if_empty_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0.ap_idle & ~start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21eDS_U' written by process 'myproject_myproject.conv_2d_cl_array_array_ap_fixed_42_16_5_3_0_32u_config18_U0',");
                        end
                    end
                    10: begin
                        if (~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0.res_blk_n) begin
                            if (~layer21_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer21_out_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer21_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer21_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer21_out_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer21_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U.if_full_n & relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0.ap_start & ~relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0.real_start & (trans_in_cnt_9 == trans_out_cnt_9) & ~start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0',");
                        end
                    end
                    endcase
                end
                10 : begin
                    case(index2)
                    9: begin
                        if (~conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0.layer21_out_blk_n) begin
                            if (~layer21_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer21_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer21_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer21_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer21_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer21_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U.if_empty_n & conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0.ap_idle & ~start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config2eES_U' written by process 'myproject_myproject.relu_array_ap_fixed_32u_array_ap_fixed_16_3_5_3_0_32u_relu_config21_U0',");
                        end
                    end
                    11: begin
                        if (~conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0.grp_compute_output_buffer_2d_array_array_ap_fixed_42_16_5_3_0_8u_config22_s_fu_889.layer22_out_blk_n) begin
                            if (~layer22_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer22_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer22_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer22_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer22_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer22_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U.if_full_n & conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0.ap_start & ~conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0.real_start & (trans_in_cnt_10 == trans_out_cnt_10) & ~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0',");
                        end
                    end
                    endcase
                end
                11 : begin
                    case(index2)
                    10: begin
                        if (~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0.data_blk_n) begin
                            if (~layer22_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer22_out_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer22_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer22_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer22_out_U' read by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer22_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U.if_empty_n & relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0.ap_idle & ~start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0_U' written by process 'myproject_myproject.conv_2d_cl_array_ap_fixed_32u_array_ap_fixed_42_16_5_3_0_8u_config22_U0',");
                        end
                    end
                    12: begin
                        if (~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0.res_blk_n) begin
                            if (~layer25_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer25_out_U' written by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer25_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer25_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer25_out_U' read by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer25_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U.if_full_n & relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0.ap_start & ~relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0.real_start & (trans_in_cnt_11 == trans_out_cnt_11) & ~start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U' read by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0',");
                        end
                    end
                    endcase
                end
                12 : begin
                    case(index2)
                    11: begin
                        if (~pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0.data_blk_n) begin
                            if (~layer25_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer25_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer25_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer25_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer25_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer25_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U.if_empty_n & pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0.ap_idle & ~start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config2eFT_U' written by process 'myproject_myproject.relu_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_relu_config25_U0',");
                        end
                    end
                    13: begin
                        if (~pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0.res_blk_n) begin
                            if (~layer26_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer26_out_U' written by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer26_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer26_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer26_out_U' read by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer26_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U.if_full_n & pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0.ap_start & ~pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0.real_start & (trans_in_cnt_12 == trans_out_cnt_12) & ~start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U' read by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0',");
                        end
                    end
                    endcase
                end
                13 : begin
                    case(index2)
                    12: begin
                        if (~dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0.layer26_out_blk_n) begin
                            if (~layer26_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer26_out_U' written by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer26_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer26_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer26_out_U' read by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer26_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U.if_empty_n & dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0.ap_idle & ~start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0_U' written by process 'myproject_myproject.pooling2d_cl_array_ap_fixed_8u_array_ap_fixed_16_3_5_3_0_8u_config26_U0',");
                        end
                    end
                    14: begin
                        if (~dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0.layer28_out_blk_n) begin
                            if (~layer28_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer28_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer28_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer28_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer28_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer28_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U.if_full_n & dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0.ap_start & ~dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0.real_start & (trans_in_cnt_13 == trans_out_cnt_13) & ~start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U' read by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0',");
                        end
                    end
                    endcase
                end
                14 : begin
                    case(index2)
                    13: begin
                        if (~relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0.data_blk_n) begin
                            if (~layer28_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer28_out_U' written by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer28_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer28_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer28_out_U' read by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer28_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U.if_empty_n & relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0.ap_idle & ~start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0_U' written by process 'myproject_myproject.dense_array_ap_fixed_8u_array_ap_fixed_44_18_5_3_0_4u_config28_U0',");
                        end
                    end
                    15: begin
                        if (~relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0.res_blk_n) begin
                            if (~layer31_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer31_out_U' written by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer31_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer31_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer31_out_U' read by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer31_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U.if_full_n & relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0.ap_start & ~relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0.real_start & (trans_in_cnt_14 == trans_out_cnt_14) & ~start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U' read by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0',");
                        end
                    end
                    endcase
                end
                15 : begin
                    case(index2)
                    14: begin
                        if (~dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0.layer31_out_blk_n) begin
                            if (~layer31_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer31_out_U' written by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer31_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer31_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer31_out_U' read by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer31_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U.if_empty_n & dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0.ap_idle & ~start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0_U' written by process 'myproject_myproject.relu_array_ap_fixed_4u_array_ap_fixed_16_3_5_3_0_4u_relu_config31_U0',");
                        end
                    end
                    16: begin
                        if (~dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0.layer32_out_blk_n) begin
                            if (~layer32_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer32_out_U' written by process 'myproject_myproject.softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer32_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer32_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer32_out_U' read by process 'myproject_myproject.softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer32_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U.if_full_n & dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0.ap_start & ~dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0.real_start & (trans_in_cnt_15 == trans_out_cnt_15) & ~start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U.if_read) begin
                            $display("//      Blocked by full output start propagation FIFO 'myproject_myproject.start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U' read by process 'myproject_myproject.softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0',");
                        end
                    end
                    endcase
                end
                16 : begin
                    case(index2)
                    15: begin
                        if (~softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0.grp_softmax_stable_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_s_fu_24.data_blk_n) begin
                            if (~layer32_out_U.if_empty_n) begin
                                $display("//      Blocked by empty input FIFO 'myproject_myproject.layer32_out_U' written by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer32_out_U");
                                $fdisplay(fp, "Dependence_Channel_status EMPTY");
                            end
                            else if (~layer32_out_U.if_full_n) begin
                                $display("//      Blocked by full output FIFO 'myproject_myproject.layer32_out_U' read by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0'");
                                $fdisplay(fp, "Dependence_Channel_path myproject_myproject.layer32_out_U");
                                $fdisplay(fp, "Dependence_Channel_status FULL");
                            end
                        end
                        if (~start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U.if_empty_n & softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0.ap_idle & ~start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U.if_write) begin
                            $display("//      Blocked by missing 'ap_start' from start propagation FIFO 'myproject_myproject.start_for_softmax_array_array_ap_fixed_16_3_5_3_0_10u_softmax_config34_U0_U' written by process 'myproject_myproject.dense_array_ap_fixed_4u_array_ap_fixed_35_9_5_3_0_10u_config32_U0',");
                        end
                    end
                    endcase
                end
            endcase
        end
    endtask

    // report
    initial begin : report_deadlock
        integer cycle_id;
        integer cycle_comp_id;
        integer record_time;
        wait (reset == 1);
        cycle_id = 1;
        record_time = 0;
        while (1) begin
            @ (negedge clock);
            case (CS_fsm)
                ST_DL_DETECTED: begin
                    cycle_comp_id = 2;
                    if (dl_detect_reg != dl_done_reg) begin
                        if (dl_done_reg == 'b0) begin
                            print_dl_head;
                            record_time = $time;
                        end
                        print_cycle_start(proc_path(origin), cycle_id);
                        cycle_id = cycle_id + 1;
                    end
                    else begin
                        print_dl_end((cycle_id - 1),record_time);
                        find_df_deadlock = 1;
                        @(negedge clock);
                        $finish;
                    end
                end
                ST_DL_REPORT: begin
                    if ((|(dl_in_vec)) & ~(|(dl_in_vec & origin_reg))) begin
                        print_cycle_chan_comp(dl_in_vec_reg, dl_in_vec);
                        print_cycle_proc_comp(proc_path(dl_in_vec), cycle_comp_id);
                        cycle_comp_id = cycle_comp_id + 1;
                    end
                    else begin
                        print_cycle_chan_comp(dl_in_vec_reg, dl_in_vec);
                    end
                end
            endcase
        end
    end
 
