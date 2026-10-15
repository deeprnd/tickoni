Run just test-integration-tk-macos-arm
Finding test binaries...
Found 1 test binaries, running sequentially...
  8b3bedbc94e09ba75a75fa403729118c... OK
All 1 tests passed.
Finding test binaries...
Found 1 test binaries, running sequentially...
  ef963465ca07b725b2b138c398c02175... OK
All 1 tests passed.
Finding test binaries...
Found 1 test binaries, running sequentially...
  805023c8154876c81768222ea442df72... OK
All 1 tests passed.
Finding test binaries...
Found 1 test binaries, running sequentially...
contrib/test/run_test_series.sh: line 61:  5156 Abort trap: 6           "$bin" > "$output_file" 2>&1
  f3a6c940bdf129cd3c6fd2e563d8a922... FAILED (exit 134)
1/12 test_metric_tile_integration.test.parsePrometheusMetric accepts counter total suffix...OK
2/12 test_metric_tile_integration.test.metric topology finalizes exact scratch requirements identically...
  [metric-test] metric_port = 35156

[topo_build debug] wksp_cnt=3 obj_cnt=40 tile_cnt=8 link_cnt=4
  wksp[0] 'topo_5156' => 34 objects
    obj[0] 'mcache' (wksp_id=0)
    obj[1] 'dcache' (wksp_id=0)
    obj[2] 'mcache' (wksp_id=0)
    obj[3] 'dcache' (wksp_id=0)
    obj[4] 'mcache' (wksp_id=0)
    obj[5] 'dcache' (wksp_id=0)
    obj[6] 'mcache' (wksp_id=0)
    obj[7] 'dcache' (wksp_id=0)
    obj[8] 'tile' (wksp_id=0)
    obj[9] 'metrics' (wksp_id=0)
    obj[10] 'tile' (wksp_id=0)
    obj[11] 'metrics' (wksp_id=0)
    obj[12] 'tile' (wksp_id=0)
    obj[13] 'metrics' (wksp_id=0)
    obj[14] 'tile' (wksp_id=0)
    obj[15] 'metrics' (wksp_id=0)
    obj[16] 'tile' (wksp_id=0)
    obj[17] 'metrics' (wksp_id=0)
    obj[18] 'tile' (wksp_id=0)
    obj[19] 'metrics' (wksp_id=0)
    obj[20] 'tile' (wksp_id=0)
    obj[21] 'metrics' (wksp_id=0)
    obj[28] 'cnc' (wksp_id=0)
    obj[29] 'cnc' (wksp_id=0)
    obj[19] 'metrics' (wksp_id=0)
    obj[20] 'tile' (wksp_id=0)
    obj[21] 'metrics' (wksp_id=0)
    obj[28] 'cnc' (wksp_id=0)
    obj[29] 'cnc' (wksp_id=0)
    obj[30] 'cnc' (wksp_id=0)
    obj[31] 'cnc' (wksp_id=0)
    obj[32] 'cnc' (wksp_id=0)
    obj[33] 'cnc' (wksp_id=0)
    obj[34] 'cnc' (wksp_id=0)
    obj[35] 'cnc' (wksp_id=0)
    obj[36] 'fseq' (wksp_id=0)
    obj[37] 'fseq' (wksp_id=0)
    obj[38] 'fseq' (wksp_id=0)
    obj[39] 'fseq' (wksp_id=0)
  wksp[1] 'metric' => 2 objects
    obj[22] 'tile' (wksp_id=1)
    obj[23] 'metrics' (wksp_id=1)
  wksp[2] 'metric_in' => 4 objects
    obj[24] 'fseq' (wksp_id=2)
    obj[25] 'fseq' (wksp_id=2)
    obj[26] 'fseq' (wksp_id=2)
    obj[27] 'fseq' (wksp_id=2)
warning: tile 2: loaded process config, stuck_tile=null, event_count=10
[cnc-write] cnc_ptr=398d6cdd9200 base=398d6cdd9240 idx=0 val=1
warning: tile 3: loaded process config, stuck_tile=null, event_count=10
[cnc-write] cnc_ptr=746e2d965280 base=746e2d9652c0 idx=0 val=8
[cnc-write] cnc_ptr=746e2d965280 base=746e2d9652c0 idx=1 val=1
Log at "/Users/runner/work/tickoni/tickoni/.zig-cache/tmp/b1G6YC0x3VM0/logs/tile_5.log"
[sup-snap] tile=tkings firedancer_idx=0 cnc=2b64aebf5100
[cnc-read] cnc_ptr=2b64aebf5100 base=2b64aebf5140 idx=0
[sup-snap] tile=tkings firedancer_idx=0 counter_idx=0 field=produced val=10
[sup-snap] tile=tknorm firedancer_idx=1 cnc=2b64aebf5180
[cnc-read] cnc_ptr=2b64aebf5180 base=2b64aebf51c0 idx=0
[sup-snap] tile=tknorm firedancer_idx=1 counter_idx=0 field=normalized val=10
[cnc-read] cnc_ptr=2b64aebf5180 base=2b64aebf51c0 idx=1
[sup-snap] tile=tknorm firedancer_idx=1 counter_idx=1 field=invalid val=0
[sup-snap] tile=tkdedu firedancer_idx=2 cnc=2b64aebf5200
[cnc-read] cnc_ptr=2b64aebf5200 base=2b64aebf5240 idx=0
[sup-snap] tile=tkdedu firedancer_idx=2 counter_idx=0 field=duplicates val=1
[sup-snap] tile=tkpoly firedancer_idx=3 cnc=2b64aebf5280
[cnc-read] cnc_ptr=2b64aebf5280 base=2b64aebf52c0 idx=0
[sup-snap] tile=tkpoly firedancer_idx=3 counter_idx=0 field=allowed val=8
[cnc-read] cnc_ptr=2b64aebf5280 base=2b64aebf52c0 idx=1
[sup-snap] tile=tkpoly firedancer_idx=3 counter_idx=1 field=denied val=1
[sup-snap] tile=tkaudt firedancer_idx=4 cnc=2b64aebf5300
[cnc-read] cnc_ptr=2b64aebf5300 base=2b64aebf5340 idx=0
[sup-snap] tile=tkaudt firedancer_idx=4 counter_idx=0 field=audited val=0
[sup-snap] tile=tkrepl firedancer_idx=5 cnc=2b64aebf5380
[cnc-read] cnc_ptr=2b64aebf5380 base=2b64aebf53c0 idx=0
[sup-snap] tile=tkrepl firedancer_idx=5 counter_idx=0 field=replay_checked val=0
[cnc-read] cnc_ptr=2b64aebf5380 base=2b64aebf53c0 idx=1
[sup-snap] tile=tkrepl firedancer_idx=5 counter_idx=1 field=replay_match val=0
[sup-snap] tile=tkdiag firedancer_idx=6 cnc=2b64aebf5480
[cnc-read] cnc_ptr=2b64aebf5480 base=2b64aebf54c0 idx=0
[sup-snap] tile=tkdiag firedancer_idx=6 counter_idx=0 field=diag_crashed_tile val=0
[cnc-read] cnc_ptr=2b64aebf5480 base=2b64aebf54c0 idx=1
[sup-snap] tile=tkdiag firedancer_idx=6 counter_idx=1 field=diag_sandbox_failures val=0
[sup-snap] tile=metric firedancer_idx=7 cnc=2b64aebf5400
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=0
[sup-snap] tile=metric firedancer_idx=7 counter_idx=0 field=metric_snapshots val=0
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=1
[sup-snap] tile=metric firedancer_idx=7 counter_idx=1 field=metric_backpressure_waits val=0
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=2
[sup-snap] tile=metric firedancer_idx=7 counter_idx=2 field=metric_boot_timestamp val=0

[topo_build debug] wksp_cnt=3 obj_cnt=40 tile_cnt=8 link_cnt=4
  wksp[0] 'topo_5161' => 34 objects
    obj[0] 'mcache' (wksp_id=0)
    obj[1] 'dcache' (wksp_id=0)
    obj[2] 'mcache' (wksp_id=0)
    obj[3] 'dcache' (wksp_id=0)
    obj[4] 'mcache' (wksp_id=0)
    obj[5] 'dcache' (wksp_id=0)
    obj[6] 'mcache' (wksp_id=0)
    obj[7] 'dcache' (wksp_id=0)
    obj[8] 'tile' (wksp_id=0)
    obj[9] 'metrics' (wksp_id=0)
    obj[10] 'tile' (wksp_id=0)
    obj[11] 'metrics' (wksp_id=0)
    obj[12] 'tile' (wksp_id=0)
    obj[13] 'metrics' (wksp_id=0)
    obj[14] 'tile' (wksp_id=0)
    obj[15] 'metrics' (wksp_id=0)
    obj[16] 'tile' (wksp_id=0)
    obj[17] 'metrics' (wksp_id=0)
    obj[18] 'tile' (wksp_id=0)
    obj[19] 'metrics' (wksp_id=0)
    obj[20] 'tile' (wksp_id=0)
    obj[21] 'metrics' (wksp_id=0)
    obj[28] 'cnc' (wksp_id=0)
    obj[29] 'cnc' (wksp_id=0)
    obj[30] 'cnc' (wksp_id=0)
    obj[31] 'cnc' (wksp_id=0)
    obj[32] 'cnc' (wksp_id=0)
    obj[33] 'cnc' (wksp_id=0)
    obj[34] 'cnc' (wksp_id=0)
    obj[35] 'cnc' (wksp_id=0)
    obj[36] 'fseq' (wksp_id=0)
    obj[37] 'fseq' (wksp_id=0)
    obj[38] 'fseq' (wksp_id=0)
    obj[39] 'fseq' (wksp_id=0)
  wksp[1] 'metric' => 2 objects
    obj[22] 'tile' (wksp_id=1)
    obj[23] 'metrics' (wksp_id=1)
  wksp[2] 'metric_in' => 4 objects
    obj[24] 'fseq' (wksp_id=2)
    obj[25] 'fseq' (wksp_id=2)
    obj[26] 'fseq' (wksp_id=2)
    obj[27] 'fseq' (wksp_id=2)
Log at "/Users/runner/work/tickoni/tickoni/.zig-cache/tmp/b1G6YC0x3VM0/logs/tile_6.log"

[topo_build debug] wksp_cnt=3 obj_cnt=40 tile_cnt=8 link_cnt=4
  wksp[0] 'topo_5161' => 34 objects
    obj[0] 'mcache' (wksp_id=0)
    obj[1] 'dcache' (wksp_id=0)
    obj[2] 'mcache' (wksp_id=0)
    obj[3] 'dcache' (wksp_id=0)
    obj[4] 'mcache' (wksp_id=0)
    obj[5] 'dcache' (wksp_id=0)
    obj[6] 'mcache' (wksp_id=0)
    obj[7] 'dcache' (wksp_id=0)
    obj[8] 'tile' (wksp_id=0)
    obj[9] 'metrics' (wksp_id=0)
    obj[10] 'tile' (wksp_id=0)
    obj[11] 'metrics' (wksp_id=0)
    obj[12] 'tile' (wksp_id=0)
    obj[13] 'metrics' (wksp_id=0)
    obj[14] 'tile' (wksp_id=0)
    obj[15] 'metrics' (wksp_id=0)
    obj[16] 'tile' (wksp_id=0)
    obj[17] 'metrics' (wksp_id=0)
    obj[18] 'tile' (wksp_id=0)
    obj[19] 'metrics' (wksp_id=0)
    obj[20] 'tile' (wksp_id=0)
    obj[21] 'metrics' (wksp_id=0)
    obj[28] 'cnc' (wksp_id=0)
    obj[29] 'cnc' (wksp_id=0)
    obj[30] 'cnc' (wksp_id=0)
    obj[31] 'cnc' (wksp_id=0)
    obj[32] 'cnc' (wksp_id=0)
    obj[33] 'cnc' (wksp_id=0)
    obj[34] 'cnc' (wksp_id=0)
    obj[35] 'cnc' (wksp_id=0)
    obj[36] 'fseq' (wksp_id=0)
    obj[37] 'fseq' (wksp_id=0)
    obj[38] 'fseq' (wksp_id=0)
    obj[39] 'fseq' (wksp_id=0)
  wksp[1] 'metric' => 2 objects
    obj[22] 'tile' (wksp_id=1)
    obj[23] 'metrics' (wksp_id=1)
  wksp[2] 'metric_in' => 4 objects
    obj[24] 'fseq' (wksp_id=2)
    obj[25] 'fseq' (wksp_id=2)
    obj[26] 'fseq' (wksp_id=2)
    obj[27] 'fseq' (wksp_id=2)
Log at "/Users/runner/work/tickoni/tickoni/.zig-cache/tmp/b1G6YC0x3VM0/logs/tile_7.log"
warning: tile 4: loaded process config, stuck_tile=null, event_count=10
[cnc-write] cnc_ptr=5a104d455300 base=5a104d455340 idx=0 val=10

[topo_build debug] wksp_cnt=3 obj_cnt=40 tile_cnt=8 link_cnt=4
  wksp[0] 'topo_5161' => 34 objects
    obj[0] 'mcache' (wksp_id=0)
    obj[1] 'dcache' (wksp_id=0)
    obj[2] 'mcache' (wksp_id=0)
    obj[3] 'dcache' (wksp_id=0)
    obj[4] 'mcache' (wksp_id=0)
    obj[5] 'dcache' (wksp_id=0)
    obj[6] 'mcache' (wksp_id=0)
    obj[7] 'dcache' (wksp_id=0)
    obj[8] 'tile' (wksp_id=0)
    obj[9] 'metrics' (wksp_id=0)
    obj[10] 'tile' (wksp_id=0)
    obj[11] 'metrics' (wksp_id=0)
    obj[12] 'tile' (wksp_id=0)
    obj[13] 'metrics' (wksp_id=0)
    obj[14] 'tile' (wksp_id=0)
    obj[15] 'metrics' (wksp_id=0)
    obj[16] 'tile' (wksp_id=0)
    obj[17] 'metrics' (wksp_id=0)
    obj[18] 'tile' (wksp_id=0)
    obj[19] 'metrics' (wksp_id=0)
    obj[20] 'tile' (wksp_id=0)
    obj[21] 'metrics' (wksp_id=0)
    obj[28] 'cnc' (wksp_id=0)
    obj[29] 'cnc' (wksp_id=0)
    obj[30] 'cnc' (wksp_id=0)
    obj[31] 'cnc' (wksp_id=0)
    obj[32] 'cnc' (wksp_id=0)
    obj[33] 'cnc' (wksp_id=0)
    obj[34] 'cnc' (wksp_id=0)
    obj[35] 'cnc' (wksp_id=0)
    obj[36] 'fseq' (wksp_id=0)
    obj[37] 'fseq' (wksp_id=0)
    obj[38] 'fseq' (wksp_id=0)
    obj[39] 'fseq' (wksp_id=0)
  wksp[1] 'metric' => 2 objects
    obj[22] 'tile' (wksp_id=1)
    obj[23] 'metrics' (wksp_id=1)
  wksp[2] 'metric_in' => 4 objects
    obj[24] 'fseq' (wksp_id=2)
    obj[25] 'fseq' (wksp_id=2)
    obj[26] 'fseq' (wksp_id=2)
    obj[27] 'fseq' (wksp_id=2)
[metric-process] boot_ts=1791988954798749000 cnc_ptr=1af96389400 idx=2
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=2 val=1791988954798749000
[metric-process] wrote boot_ts=1791988954798749000 to cnc index 2
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=1
[sup-snap] tile=tkings firedancer_idx=0 cnc=2b64aebf5100
[cnc-read] cnc_ptr=2b64aebf5100 base=2b64aebf5140 idx=0
[sup-snap] tile=tkings firedancer_idx=0 counter_idx=0 field=produced val=10
[sup-snap] tile=tknorm firedancer_idx=1 cnc=2b64aebf5180
[cnc-read] cnc_ptr=2b64aebf5180 base=2b64aebf51c0 idx=0
[sup-snap] tile=tknorm firedancer_idx=1 counter_idx=0 field=normalized val=10
[cnc-read] cnc_ptr=2b64aebf5180 base=2b64aebf51c0 idx=1
[sup-snap] tile=tknorm firedancer_idx=1 counter_idx=1 field=invalid val=0
[sup-snap] tile=tkdedu firedancer_idx=2 cnc=2b64aebf5200
[cnc-read] cnc_ptr=2b64aebf5200 base=2b64aebf5240 idx=0
[sup-snap] tile=tkdedu firedancer_idx=2 counter_idx=0 field=duplicates val=1
[sup-snap] tile=tkpoly firedancer_idx=3 cnc=2b64aebf5280
[cnc-read] cnc_ptr=2b64aebf5280 base=2b64aebf52c0 idx=0
[sup-snap] tile=tkpoly firedancer_idx=3 counter_idx=0 field=allowed val=8
[cnc-read] cnc_ptr=2b64aebf5280 base=2b64aebf52c0 idx=1
[sup-snap] tile=tkpoly firedancer_idx=3 counter_idx=1 field=denied val=1
[sup-snap] tile=tkaudt firedancer_idx=4 cnc=2b64aebf5300
[cnc-read] cnc_ptr=2b64aebf5300 base=2b64aebf5340 idx=0
[sup-snap] tile=tkaudt firedancer_idx=4 counter_idx=0 field=audited val=10
[sup-snap] tile=tkrepl firedancer_idx=5 cnc=2b64aebf5380
[cnc-read] cnc_ptr=2b64aebf5380 base=2b64aebf53c0 idx=0
[sup-snap] tile=tkrepl firedancer_idx=5 counter_idx=0 field=replay_checked val=0
[cnc-read] cnc_ptr=2b64aebf5380 base=2b64aebf53c0 idx=1
[sup-snap] tile=tkrepl firedancer_idx=5 counter_idx=1 field=replay_match val=0
[sup-snap] tile=tkdiag firedancer_idx=6 cnc=2b64aebf5480
[cnc-read] cnc_ptr=2b64aebf5480 base=2b64aebf54c0 idx=0
[sup-snap] tile=tkdiag firedancer_idx=6 counter_idx=0 field=diag_crashed_tile val=0
[cnc-read] cnc_ptr=2b64aebf5480 base=2b64aebf54c0 idx=1
[sup-snap] tile=tkdiag firedancer_idx=6 counter_idx=1 field=diag_sandbox_failures val=0
[sup-snap] tile=metric firedancer_idx=7 cnc=2b64aebf5400
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=0
[sup-snap] tile=metric firedancer_idx=7 counter_idx=0 field=metric_snapshots val=1
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=1
[sup-snap] tile=metric firedancer_idx=7 counter_idx=1 field=metric_backpressure_waits val=0
[cnc-read] cnc_ptr=2b64aebf5400 base=2b64aebf5440 idx=2
[sup-snap] tile=metric firedancer_idx=7 counter_idx=2 field=metric_boot_timestamp val=1791988954798749000
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=2
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=3
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=4
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=5
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=6
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=7
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=8
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=9
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=10
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=11
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=12
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=13
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=14
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=15
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=16
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=17
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=18
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=19
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=20
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=21
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=22
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=23
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=24
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=25
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=26
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=27
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=28

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=29
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=30
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=31
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=32
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=33

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=34
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=35
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=36
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=37
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=38
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=39
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=40

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=41
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=42
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=43
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=44
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=45
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=46
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=47

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=48
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=49
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=50
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=51
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=52
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=53
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=54
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=55

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=56
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=57
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=58
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=59
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=60
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=61
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=62
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=63
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=64

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=65
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=66
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=67
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=68
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=69
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=70
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=71

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=72
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=73
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=74
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=75
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=76
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=77

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=78
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=79
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=80
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=81
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=82
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=83

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=84
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=85
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=86
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=87
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=88
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=89

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=90
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=91
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=92
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=93
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=94
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=95
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=96

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=97
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=98
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=99
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=100
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=101
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=102
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=103

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=104
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=105
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=106
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=107
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=108

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=109
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=110
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=111
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=112
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=113
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=114
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=115

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=116
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=117
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=118
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=119
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=120

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=121
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=122
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=123
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=124
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=125
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=126
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=127

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=128
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=129
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=130
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=131
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=132
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=133
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=134
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=135

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=136
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=137
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=138
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=139
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=140
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=141
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=142

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=143
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=144
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=145
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=146
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=147
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=148
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=149

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=150
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=151
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=152
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=153
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=154
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=155

[metric-http-debug] response stdout={"status_code": 0, "body": "", "error": "<urlopen error [Errno 61] Connection refused>"}

[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=156
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=157
thread 15756 panic: Failed to connect to HTTP server on port 35160: ConnectionTimeout
error return context:
/Users/runner/work/tickoni/tickoni/src/tickoni/test/integration/test_metric_tile_integration.zig:149:5: 0x104fd10db in httpGetWithRetry (test)
    return error.ConnectionTimeout;
    ^

stack trace:
/Users/runner/work/tickoni/tickoni/src/tickoni/test/integration/test_metric_tile_integration.zig:547:24: 0x104ff94bf in test.metric_tile_integration: unknown path returns HTTP 404 (test)
        std.debug.panic("Failed to connect to HTTP server on port {d}: {s}", .{ port, @errorName(err) });
                       ^
/Users/runner/.local/zig-aarch64-macos-0.17.0/lib/compiler/test_runner.zig:295:25: 0x104f67343 in mainTerminal (test)
        if (test_fn.func()) |_| {
                        ^
/Users/runner/.local/zig-aarch64-macos-0.17.0/lib/compiler/test_runner.zig:74:28: 0x104f66e23 in main (test)
        return mainTerminal(init);
                           ^
/Users/runner/.local/zig-aarch64-macos-0.17.0/lib/std/start.zig:789:88: 0x104f64d53 in callMain (test)
    if (fn_info.param_types[0].? == std.process.Init.Minimal) return wrapMain(root.main(.{
                                                                                       ^
???:?:?: 0x18f88ab97 in start (/usr/lib/dyld)
ERR     10-14 14:42:37.573998 5156   e-1  0    fd_log.c(940): Received signal SIGABRT-Aborted
0x104e39180 0   test                                0x0000000104e39180 fd_log_private_sig_abort + 136
0x18fc656a4 0   libsystem_platform.dylib            0x000000018fc656a4 _sigtramp + 56
0x18fc2b848 0   libsystem_pthread.dylib             0x000000018fc2b848 pthread_kill + 296
0x18fb34af0 0   libsystem_c.dylib                   0x000000018fb34af0 abort + 124
0x104e57b84 0   test                                0x0000000104e57b84 process.abort + 20
0x104e57764 0   test                                0x0000000104e57764 debug.defaultPanic + 156
0x104ff9858 0   test                                0x0000000104ff9858 debug.panicExtra__func_1558 + 184
0x104ff978c 0   test                                0x0000000104ff978c testing.failPrint__func_1557 + 0
0x104ff94c0 0   test                                0x0000000104ff94c0 test_metric_tile_integration.test.metric_tile_integration: unknown path returns HTTP 404 + 1340
0x104f67344 0   test                                0x0000000104f67344 test_runner.mainTerminal + 836
0x104f66e24 0   test                                0x0000000104f66e24 test_runner.main + 1060
0x104f64d54 0   test                                0x0000000104f64d54 main + 632
0x18f88ab98 0   dyld                                0x000000018f88ab98 start + 6076
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=158
[cnc-write] cnc_ptr=1af96389400 base=1af96389440 idx=0 val=159
FAIL: 1 of 1 tests failed (0 passed)
integration-test
+- integration-test-infra
   +- run bash
      +- run bash
         +- run bash
            +- run bash
               +- run bash
                  +- run bash failure
error: process exited with code 1
failed command: cd . && bash contrib/test/run_test_series.sh ./build/.zig-cache/o/f3a6c940bdf129cd3c6fd2e563d8a922/test


Finding test binaries...
Found 1 test binaries, running sequentially...
  605a729e3254a1cea1ecec4a405c5154... OK
All 1 tests passed.
Finding test binaries...
Found 1 test binaries, running sequentially...
  e3666f482f6e782caee4c1f30af3f231... OK
All 1 tests passed.
Finding test binaries...
Found 1 test binaries, running sequentially...
  4766fe0c9134b40850a5dec05eb1b107... OK
All 1 tests passed.
Build Summary: 26/36 steps succeeded (1 failed)
integration-test transitive failure
+- integration-test-infra transitive failure
   +- run bash failure
   +- run bash transitive failure
   |  +- run bash (+2 more reused dependencies)
   +- run bash transitive failure
   |  +- run bash (+3 more reused dependencies)
   +- run bash transitive failure
   |  +- run bash (+3 more reused dependencies)
   +- run bash transitive failure
   |  +- run bash (+3 more reused dependencies)
   +- run bash transitive failure
   |  +- run bash (+3 more reused dependencies)
   +- run bash transitive failure
   |  +- run bash (+3 more reused dependencies)
   +- run bash transitive failure
      +- run bash (+3 more reused dependencies)

error: recipe `test-integration-tk-macos-arm` failed with exit code 1
Error: Process completed with exit code 1.
