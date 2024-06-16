package benchmark

import "core:time"
import "core:log"

run_benchmark :: proc(work: proc(), pre: proc(), post: proc(), iterations: u32, description: string) {
    log.info("Running benchmark:", description)
    total_duration := time.Duration(0)
    for i in 0..<iterations {
        pre()
        start_time := time.now()
        work()
        end_time := time.now()
        total_duration += time.diff(start_time, end_time)
        post()
    }
    ns := f64(time.duration_nanoseconds(total_duration) / i64(iterations))
    log.infof("Average duration: %f us", ns / 1_000)
}

main :: proc() {
	context.logger = log.create_console_logger()

    test_create_1_entity()
    test_create_100_entity()
    test_create_10000_entity()

    test_add_1_component()
    test_add_100_component()
    test_add_10000_component()

    test_set_1_component()
    test_set_100_component()
    test_set_10000_component()

    test_set_1_existing_component()
    test_set_100_existing_component()
    test_set_10000_existing_component()
}