#import "USearchObjective.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import <usearch/index_dense.hpp>
#pragma clang diagnostic pop

using namespace unum::usearch;
using namespace unum;

using distance_t = distance_punned_t;
using add_result_t = typename index_dense_t::add_result_t;
using labeling_result_t = typename index_dense_t::labeling_result_t;
using search_result_t = typename index_dense_t::search_result_t;
using shared_index_dense_t = std::shared_ptr<index_dense_t>;

NSErrorDomain const USearchErrorDomain = @"cloud.unum.usearch.USearchErrorDomain";

static_assert(std::is_same<USearchKey, index_dense_t::vector_key_t>::value, "Type mismatch between Objective-C and C++");

metric_kind_t to_native_metric(USearchMetric m) {
    switch (m) {
        case USearchMetricIP:
            return metric_kind_t::ip_k;

        case USearchMetricCos:
            return metric_kind_t::cos_k;

        case USearchMetricL2sq:
            return metric_kind_t::l2sq_k;

        case USearchMetricHamming:
            return metric_kind_t::hamming_k;

        case USearchMetricHaversine:
            return metric_kind_t::haversine_k;

        case USearchMetricDivergence:
            return metric_kind_t::divergence_k;

        case USearchMetricJaccard:
            return metric_kind_t::jaccard_k;

        case USearchMetricPearson:
            return metric_kind_t::pearson_k;

        case USearchMetricSorensen:
            return metric_kind_t::sorensen_k;

        case USearchMetricTanimoto:
            return metric_kind_t::tanimoto_k;

        default:
            return metric_kind_t::unknown_k;
    }
}

scalar_kind_t to_native_scalar(USearchScalar m) {
    switch (m) {
        case USearchScalarI8:
            return scalar_kind_t::i8_k;

        case USearchScalarF16:
            return scalar_kind_t::f16_k;

        case USearchScalarBF16:
            return scalar_kind_t::bf16_k;

        case USearchScalarF32:
            return scalar_kind_t::f32_k;

        case USearchScalarF64:
            return scalar_kind_t::f64_k;

        default:
            return scalar_kind_t::unknown_k;
    }
}

@interface USearchIndex ()

@property (readonly) shared_index_dense_t native;

- (instancetype)initWithIndex:(shared_index_dense_t)native;

@end

@implementation USearchIndex

- (instancetype)initWithIndex:(shared_index_dense_t)native {
    self = [super init];
    _native = native;
    return self;
}

- (Boolean)isEmpty {
    return _native->size() != 0;
}

- (UInt32)dimensions {
    return static_cast<UInt32>(_native->dimensions());
}

- (UInt32)connectivity {
    return static_cast<UInt32>(_native->connectivity());
}

- (UInt32)length {
    return static_cast<UInt32>(_native->size());
}

- (UInt32)capacity {
    return static_cast<UInt32>(_native->capacity());
}

- (UInt32)expansionAdd {
    return static_cast<UInt32>(_native->expansion_add());
}

- (UInt32)expansionSearch {
    return static_cast<UInt32>(_native->expansion_search());
}

+ (instancetype)make:(USearchMetric)metricKind
          dimensions:(UInt32)dimensions
        connectivity:(UInt32)connectivity
        quantization:(USearchScalar)quantization
               error:(NSError**)error {
    // Create a single-vector index by default
    return [self make:metricKind dimensions:dimensions connectivity:connectivity quantization:quantization multi:false error:error];
}

+ (instancetype)make:(USearchMetric)metricKind
          dimensions:(UInt32)dimensions
        connectivity:(UInt32)connectivity
        quantization:(USearchScalar)quantization
               multi:(BOOL)multi
               error:(NSError**)error {
    std::size_t dims = static_cast<std::size_t>(dimensions);

    index_dense_config_t config(static_cast<std::size_t>(connectivity));
    config.multi = multi;
    metric_punned_t metric(dims, to_native_metric(metricKind), to_native_scalar(quantization));
    if (metric.missing()) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchUnsupportedMetric
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't create an index",
            NSLocalizedFailureReasonErrorKey: @"The metric is not supported",
        }];
        return nil;
    }

    shared_index_dense_t ptr = std::make_shared<index_dense_t>(index_dense_t::make(metric, config));
    return [[USearchIndex alloc] initWithIndex:ptr];
}

- (void)addSingle:(USearchKey)key
           vector:(Float32 const *_Nonnull)vector
            error:(NSError**)error {
    add_result_t result = _native->add(key, vector);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchAddError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't add to index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (UInt32)searchSingle:(Float32 const *_Nonnull)vector
                 count:(UInt32)wanted
                  keys:(USearchKey *_Nullable)keys
             distances:(Float32 *_Nullable)distances
                 error:(NSError**)error {
    search_result_t result = _native->search(vector, static_cast<std::size_t>(wanted));

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchFindError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't find in index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
        return 0;
    }

    std::size_t found = result.dump_to(keys, distances);
    return static_cast<UInt32>(found);
}

- (UInt32)getSingle:(USearchKey)key
             vector:(void *_Nonnull)vector
              count:(UInt32)wanted
              error:(NSError**)error {
    std::size_t result = _native->get(key, (f32_t*)vector, static_cast<std::size_t>(wanted));
    return static_cast<UInt32>(result);
}

- (UInt32)filteredSearchSingle:(Float32 const *_Nonnull)vector
                 count:(UInt32)wanted
                filter:(USearchFilterFn)predicate
                  keys:(USearchKey *_Nullable)keys
             distances:(Float32 *_Nullable)distances
                 error:(NSError**)error {
    search_result_t result = _native->filtered_search(vector, static_cast<std::size_t>(wanted), predicate);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchFindError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't find in index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
        return 0;
    }

    std::size_t found = result.dump_to(keys, distances);
    return static_cast<UInt32>(found);
}

- (void)addDouble:(USearchKey)key
           vector:(Float64 const *_Nonnull)vector
            error:(NSError**)error {
    add_result_t result = _native->add(key, (f64_t const *)vector);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchAddError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't add to index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (UInt32)searchDouble:(Float64 const *_Nonnull)vector
                 count:(UInt32)wanted
                  keys:(USearchKey *_Nullable)keys
             distances:(Float32 *_Nullable)distances
                 error:(NSError**)error {
    search_result_t result = _native->search((f64_t const *)vector, static_cast<std::size_t>(wanted));

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchFindError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't find in index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
        return 0;
    }

    std::size_t found = result.dump_to(keys, distances);
    return static_cast<UInt32>(found);
}

- (UInt32)getDouble:(USearchKey)key
             vector:(void *_Nonnull)vector
              count:(UInt32)wanted
              error:(NSError**)error {
    std::size_t result = _native->get(key, (f64_t*)vector, static_cast<std::size_t>(wanted));
    return static_cast<UInt32>(result);
}

- (UInt32)filteredSearchDouble:(Float64 const *_Nonnull)vector
                 count:(UInt32)wanted
                filter:(USearchFilterFn)predicate
                  keys:(USearchKey *_Nullable)keys
             distances:(Float32 *_Nullable)distances
                 error:(NSError**)error {
    search_result_t result = _native->filtered_search((f64_t const *) vector, static_cast<std::size_t>(wanted), predicate);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchFindError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't find in index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
        return 0;
    }

    std::size_t found = result.dump_to(keys, distances);
    return static_cast<UInt32>(found);
}

- (void)addHalf:(USearchKey)key
         vector:(void const *_Nonnull)vector
          error:(NSError**)error {
    add_result_t result = _native->add(key, (f16_t const *)vector);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchAddError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't add to index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (UInt32)searchHalf:(void const *_Nonnull)vector
               count:(UInt32)wanted
                keys:(USearchKey *_Nullable)keys
           distances:(Float32 *_Nullable)distances
               error:(NSError**)error {
    search_result_t result = _native->search((f16_t const *)vector, static_cast<std::size_t>(wanted));

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchFindError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't find in index",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
        return 0;
    }

    std::size_t found = result.dump_to(keys, distances);
    return static_cast<UInt32>(found);
}

- (UInt32)getHalf:(USearchKey)key
           vector:(void *_Nonnull)vector
            count:(UInt32)wanted
            error:(NSError**)error {
    std::size_t result = _native->get(key, (f16_t*)vector, static_cast<std::size_t>(wanted));
    return static_cast<UInt32>(result);
}

- (void)clear:(NSError**)error {
    _native->clear();
}

- (void)reserve:(UInt32)count error:(NSError**)error {
    if (!_native->try_reserve(static_cast<std::size_t>(count))) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchAllocationError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't reserve space",
            NSLocalizedFailureReasonErrorKey: @"Memory allocation failed",
        }];
    }
}

- (Boolean)contains:(USearchKey)key error:(NSError**)error {
    return _native->contains(key);
}

- (UInt32)count:(USearchKey)key error:(NSError**)error {
    return static_cast<UInt32>(_native->count(key));
}

- (void)remove:(USearchKey)key
         error:(NSError**)error {
    labeling_result_t result = _native->remove(key);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchRemoveError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't remove an entry",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (void)rename:(USearchKey)key to:(USearchKey)to error:(NSError**)error {
    labeling_result_t result = _native->rename(key, to);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchRenameError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't rename the entry",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (void)save:(NSString *)path error:(NSError**)error {
    char const *path_c = [path UTF8String];

    if (!path_c) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchPathNotUTF8Encodable
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't save to disk",
            NSLocalizedFailureReasonErrorKey: @"The path must be convertible to UTF8",
        }];
        return;
    }

    serialization_result_t result = _native->save(path_c);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchSaveError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't save to disk",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (void)load:(NSString *)path error:(NSError**)error {
    char const *path_c = [path UTF8String];

    if (!path_c) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchPathNotUTF8Encodable
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't load from disk",
            NSLocalizedFailureReasonErrorKey: @"The path must be convertible to UTF8",
        }];
        return;
    }

    serialization_result_t result = _native->load(path_c);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchLoadError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't load from disk",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

- (void)view:(NSString *)path error:(NSError**)error {
    char const *path_c = [path UTF8String];

    if (!path_c) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchPathNotUTF8Encodable
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't view from disk",
            NSLocalizedFailureReasonErrorKey: @"The path must be convertible to UTF8",
        }];
        return;
    }

    serialization_result_t result = _native->view(path_c);

    if (!result) {
        *error = [NSError errorWithDomain:USearchErrorDomain
                                     code:USearchViewError
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Can't view from disk",
            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:result.error.release()],
        }];
    }
}

@end
