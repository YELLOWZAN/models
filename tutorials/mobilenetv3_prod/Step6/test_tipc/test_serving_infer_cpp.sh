#!/bin/bash
source test_tipc/common_func.sh

FILENAME=$1
dataline=$(awk 'NR==1, NR==18{print}'  $FILENAME)
MODE=$2

# parser params
IFS=$'\n'
lines=(${dataline})

# parser serving
model_name=$(func_parser_value "${lines[1]}")
python_list=$(func_parser_value "${lines[2]}")
trans_model_py=$(func_parser_value "${lines[3]}")
infer_model_dir_key=$(func_parser_key "${lines[4]}")
infer_model_dir_value=$(func_parser_value "${lines[4]}")
model_filename_key=$(func_parser_key "${lines[5]}")
model_filename_value=$(func_parser_value "${lines[5]}")
params_filename_key=$(func_parser_key "${lines[6]}")
params_filename_value=$(func_parser_value "${lines[6]}")
serving_server_key=$(func_parser_key "${lines[7]}")
serving_server_value=$(func_parser_value "${lines[7]}")
serving_client_key=$(func_parser_key "${lines[8]}")
serving_client_value=$(func_parser_value "${lines[8]}")
serving_dir_value=$(func_parser_value "${lines[9]}")
run_model_path_key=$(func_parser_key "${lines[10]}")
run_model_path_value=$(func_parser_value "${lines[10]}")
op_key=$(func_parser_key "${lines[11]}")
op_value=$(func_parser_value "${lines[11]}")
port_key=$(func_parser_key "${lines[12]}")
port_value=$(func_parser_value "${lines[12]}")
gpu_key=$(func_parser_key "${lines[13]}")
gpu_value=$(func_parser_value "${lines[13]}")
cpp_client_value=$(func_parser_value "${lines[14]}")
proto_path=$(func_parser_value "${lines[15]}")

LOG_PATH="./test_tipc/output/${model_name}/${MODE}"
mkdir -p ${LOG_PATH}
status_log="${LOG_PATH}/serving_infer_cpp.log"

function func_serving(){
    IFS='|'
    _python=$1
    _script=$2
    _model_dir=$3

    # phrase 1: save model
    set_dirname=$(func_set_params "${infer_model_dir_key}" "${infer_model_dir_value}")
    set_model_filename=$(func_set_params "${model_filename_key}" "${model_filename_value}")
    set_params_filename=$(func_set_params "${params_filename_key}" "${params_filename_value}")
    set_serving_server=$(func_set_params "${serving_server_key}" "${serving_server_value}")
    set_serving_client=$(func_set_params "${serving_client_key}" "${serving_client_value}")
    python_list=(${python_list})
    python=${python_list[0]}
    trans_model_cmd="${python} ${trans_model_py} ${set_dirname} ${set_model_filename} ${set_params_filename} ${set_serving_server} ${set_serving_client}"
    eval $trans_model_cmd
    last_status=${PIPESTATUS[0]}
    cp ${proto_path} ${serving_client_value}
    cd ${serving_dir_value}
    status_check $last_status "${trans_model_cmd}" "${status_log}" "${model_name}"
    echo $PWD
    unset https_proxy
    unset http_proxy

    # phrase 2: run server
    for gpu_id in ${gpu_value[*]}; do
        cat gpu_id
        if [ ${gpu_id} = "null" ]; then
            _save_log_path="${LOG_PATH}/cpp_server_cpu.log"
            cpp_server_cmd="${python} -m paddle_serving_server.serve ${run_model_path_key} ${run_model_path_value} ${op_key} ${op_value} ${port_key} ${port_value} > ${_save_log_path} 2>&1 "
            eval $cpp_server_cmd
            last_status=${PIPESTATUS[0]}
            status_check $last_status "${cpp_server_cmd}" "${status_log}" "${model_name}"
            sleep 5s
            _save_infer_log_path="${LOG_PATH}/cpp_client_cpu.log"
            clinet_cmd="${python} ${cpp_client_value} > ${_save_infer_log_path} 2>&1 "
            eval $clinet_cmd
            last_status=${PIPESTATUS[0]}
            status_check $last_status "${clinet_cmd}" "${status_log}" "${model_name}"
            # eval "cat ${_save_log_path}"
            ps ux | grep -i ${port_value} | awk '{print $2}' | xargs kill -s 9
        else
            _save_log_path="${LOG_PATH}/cpp_server_gpu.log"
            cpp_server_cmd="${python} -m paddle_serving_server.serve ${run_model_path_key} ${run_model_path_value} ${op_key} ${op_value} ${port_key} ${port_value} ${gpu_key} ${gpu_id} > ${_save_log_path} 2>&1 "
            eval $cpp_server_cmd
            last_status=${PIPESTATUS[0]}
            status_check $last_status "${cpp_server_cmd}" "${status_log}" "${model_name}"
            sleep 5s
            _save_infer_log_path="${LOG_PATH}/cpp_client_gpu.log"
            clinet_cmd="${python} ${cpp_client_value} > ${_save_infer_log_path} 2>&1 "
            eval $clinet_cmd
            last_status=${PIPESTATUS[0]}
            status_check $last_status "${clinet_cmd}" "${status_log}" "${model_name}"
            # eval "cat ${_save_log_path}"
            ps ux | grep -i ${port_value} | awk '{print $2}' | xargs kill -s 9
        fi
    done

}


# set cuda device
GPUID=$3
if [ ${#GPUID} -le 0 ];then
    env=" "
else
    env="export CUDA_VISIBLE_DEVICES=${GPUID}"
fi
set CUDA_VISIBLE_DEVICES
eval $env


echo "################### run test ###################"

export Count=0
IFS="|"
func_serving "${web_service_cmd}"
