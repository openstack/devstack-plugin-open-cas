# Devstack open-cas plugin

OPENCAS_REPO_DIR=${DEST:-/}
OPENCAS_REPO_URL=${OPENCAS_REPO_URL:-https://github.com/Open-CAS/open-cas-linux.git}
OPENCAS_REPO_BRANCH=master
OPENCAS_CACHE_SIZE=${OPENCAS_CACHE_SIZE:-1048576}


function git_clone_opencas {
    cd $OPENCAS_REPO_DIR
    git clone $OPENCAS_REPO_URL $OPENCAS_REPO_DIR/open-cas-linux -b $OPENCAS_REPO_BRANCH
    cd open-cas-linux
    git submodule update --init
}

function compile_opencas {
    if is_ubuntu; then
        install_package linux-headers-$(uname -r) gcc
    elif is_fedora; then
        install_package kernel-headers.x86_64 kernel-devel.x86_64 gcc
    else
        exit_distro_not_supported "installing packages"
    fi
    sudo ./configure
    make
}

function install_opencas {
    sudo make install
    sudo casadm -V
}

function create_cache_instance {
    sudo modprobe brd rd_nr=1 rd_size=$OPENCAS_CACHE_SIZE max_part=0
    RAM_DEV=/dev/ram0
    sudo casadm -S -d $RAM_DEV -f
    sudo casadm -L
}

function remove_cores {
    cache_id=""
    core_id=""
    (sudo casadm -L) | while read line ; do
    col1=$(echo $line | awk '{print $1}')
    col2=$(echo $line | awk '{print $2}')
    if [[ "$col1" =~ cache ]]; then
        cache_id=$col2
    fi
    if [[ "$col1" =~ core ]]; then
        core_id=$col2
        sudo casadm -R -i $cache_id -j $core_id -f
    fi
    done
}

function remove_cache_instance {
    (sudo casadm -L) | while read line ; do
    col1=$(echo $line | awk '{print $1}')
    col2=$(echo $line | awk '{print $2}')
    if [[ "$col1" =~ cache ]]; then
        cache_id=$col2
        sudo casadm -T -i $cache_id
    fi
    done
}

function uninstall_opencas {
    cd $OPENCAS_REPO_DIR
    cd open-cas-linux
    pwd
    sudo make uninstall
}

if [[ "$1" == "stack" && "$2" == "pre-install" ]]; then
    echo_summary "git clone open-cas"
    git_clone_opencas
    echo_summary "compile open-cas"
    compile_opencas
    echo_summary "Install open-cas"
    install_opencas
    echo_summary "create cache instance"
    create_cache_instance
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    # configure open-cas in /path/to/nova-cpu.conf
    iniset $NOVA_CPU_CONF compute volume_local_cache_driver opencas
    iniset $NOVA_CPU_CONF compute volume_local_cache_instance_ids 1
    iniset $TEMPEST_CONFIG volume-feature-enabled volume_local_cache True
fi

if [[ "$1" == "unstack" ]]; then
    sudo casadm -L
    echo_summary "remove cores"
    remove_cores
    echo_summary "remove cache instance"
    remove_cache_instance
    echo_summary "uninstall opencas"
    uninstall_opencas
fi
