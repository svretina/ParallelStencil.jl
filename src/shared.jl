# Enable CUDA/AMDGPU if the required packages are installed or in any case (enables to use the package for CPU-only without requiring the CUDA/AMDGPU packages functional - or even not at all if the installation procedure allows it). NOTE: it cannot be precompiled for GPU on a node without GPU.
import .ParallelKernel: ENABLE_CUDA, ENABLE_AMDGPU  # ENABLE_CUDA and ENABLE_AMDGPU must also always be accessible from the unit tests
@static if ENABLE_CUDA && ENABLE_AMDGPU
    using CUDA
    using AMDGPU
elseif ENABLE_CUDA 
    using CUDA
elseif ENABLE_AMDGPU
    using AMDGPU
end
import MacroTools: @capture, postwalk # NOTE: inexpr_walk used instead of MacroTools.inexpr
import .ParallelKernel: eval_arg, split_args, split_kwargs, extract_posargs_init, extract_kernel_args, is_kernel, is_call, gensym_world, isgpu, @isgpu, substitute, inexpr_walk
import .ParallelKernel: PKG_CUDA, PKG_AMDGPU, PKG_THREADS, PKG_NONE, NUMBERTYPE_NONE, SUPPORTED_NUMBERTYPES, SUPPORTED_PACKAGES, ERRMSG_UNSUPPORTED_PACKAGE, INT_CUDA, INT_AMDGPU, INT_THREADS, INDICES, PKNumber, RANGES_VARNAME, RANGES_TYPE, RANGELENGTHS_VARNAMES, THREADIDS_VARNAMES
import .ParallelKernel: @require, @symbols, symbols, longnameof, @prettyexpand, @prettystring, prettystring, @gorgeousexpand, @gorgeousstring, gorgeousstring


## CONSTANTS

const WITHIN_DOC = """
    @within(macroname::String, A::Symbol)

Return an expression that evaluates to `true` if the indices generated by @parallel (module ParallelStencil) point to elements in bounds of the selection of `A` by `macroname`.

!!! warning
    This macro is not intended for explicit manual usage. Calls to it are automatically added by @parallel where required.
"""

const SUPPORTED_NDIMS           = [1, 2, 3]
const NDIMS_NONE                = 0
const ERRMSG_KERNEL_UNSUPPORTED = "unsupported kernel statements in @parallel kernel definition: @parallel is only applicable to kernels that contain exclusively array assignments using macros from FiniteDifferences{1|2|3}D or from another compatible computation submodule. @parallel_indices supports any kind of statements in the kernels."
const ERRMSG_CHECK_NDIMS        = "ndims must be noted LITERALLY (NOT a variable containing the ndims) and has to be one of the following: $(join(SUPPORTED_NDIMS,", "))"
const PSNumber                  = PKNumber
const LOOPSIZE                  = 16
const NTHREADS_MAX_LOOPOPT      = 128
const NOEXPR                    = :(begin end)

## FUNCTIONS TO DEAL WITH KERNEL DEFINITIONS

function validate_body(body::Expr)
    statements = (body.head == :block) ? body.args : [body]
    for statement in statements
        if !(isa(statement, LineNumberNode) || isa(statement, Expr))
            @ArgumentError(ERRMSG_KERNEL_UNSUPPORTED)
        end
        if isa(statement, Expr)
            if (statement.head != :(=)) || !isa(statement.args[1], Expr) || statement.args[1].head != :macrocall
                @ArgumentError(ERRMSG_KERNEL_UNSUPPORTED)
            end
        end
    end
end


## FUNCTIONS FOR ERROR HANDLING

check_ndims(ndims) = ( if !isa(ndims, Integer) || !(ndims in SUPPORTED_NDIMS) @ArgumentError("$ERRMSG_CHECK_NDIMS (obtained: $ndims)." ) end )
