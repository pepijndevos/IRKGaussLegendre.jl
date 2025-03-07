#
#   Auxiliarfunctions.jl file:
#       ErrorEst:
#       MyNorm
#       Rdigits

function ErrorEst(U, F, dt, beta, abstol, reltol)
    uiType = eltype(U[1])
    realuiType = real(uiType)

    (s,) = size(F)
    D = length(U[1])

    est = zero(realuiType)

    @inbounds begin
        for k in eachindex(U[1])
            sum = zero(realuiType)
            maxU = zero(realuiType)
            for is in 1:s
                sum += beta[is] * F[is][k]
                maxU = max(maxU, abs(U[is][k]))
            end

            est += (abs(dt * sum))^2 / (abstol + maxU^2 * reltol)
        end
    end

    return (est / D)
end

function MyNorm(u, abstol, reltol)
    uiType = eltype(u)

    realuiType = real(uiType)
    norm = zero(realuiType)

    if uiType <: Complex
        @inbounds begin
            for k in eachindex(u)
                aux = u[k] / (abstol + abs(u[k]) * reltol)
                norm += aux * conj(aux)
            end
        end
    else
        @inbounds begin
            for k in eachindex(u)
                aux = u[k] / (abstol + abs(u[k]) * reltol)
                norm += aux * aux
            end
        end
    end

    norm = sqrt(norm / (length(u)))

    return (real(norm))
end

function Rdigits(x, r::Integer)
    mx = r * x
    mxx = mx + x
    return (mxx - mx)
end
