
#
#  IRKstep_fixed!
#  IRKstep_fixed_Mix!
#  IRKstepDynODE_fixed!

function IRKstep_fixed!(s,
    j,
    ttj,
    uj,
    ej,
    prob,
    dts,
    coeffs,
    cache,
    maxiters,
    initial_interp,
    abstol,
    reltol,
    adaptive,
    threading)
    @unpack mu, hc, hb, nu, alpha = coeffs
    @unpack f, u0, p, tspan = prob
    @unpack U, Uz, L, Lz, F, Dmin, Eval, DY, rejects, nfcn, lambdas, nrmdigits = cache

    uiType = eltype(uj)
    realuiType = real(uiType)

    dt = dts[1]
    dtprev = dts[2]
    tf = tspan[2]

    elems = s * length(uj)

    tj = ttj[1]
    te = ttj[2]

    nit = 0

    if (dt != dtprev)
        HCoefficients!(mu, hc, hb, nu, dt, dtprev, realuiType)
        @unpack mu, hc, hb, nu, alpha = coeffs
    end

    if initial_interp
        @inbounds begin
            for is in 1:s
                for k in eachindex(uj)
                    aux = zero(eltype(uj))
                    for js in 1:s
                        aux += nu[is, js] * L[js][k]
                    end
                    U[is][k] = (uj[k] + ej[k]) + aux
                end
            end
        end
    else
        @inbounds begin
            for is in 1:s
                @. U[is] = uj + ej
            end
        end
    end

    iter = true
    plusIt = true

    nit = 0
    @inbounds begin
        for is in 1:s
            Dmin[is] .= Inf
        end
    end

    @inbounds begin
        for is in 1:s
            nfcn[1] += 1
            f(F[is], U[is], p, tj + hc[is])
            @. L[is] = hb[is] * F[is]
        end
    end

    while (nit < maxiters && iter)
        nit += 1

        iter = false
        D0 = 0

        @inbounds begin
            for is in 1:s
                Uz[is] .= U[is]
                DiffEqBase.@.. U[is] = uj + (ej +
                                        mu[is, 1] * L[1] +
                                        mu[is, 2] * L[2] +
                                        mu[is, 3] * L[3] +
                                        mu[is, 4] * L[4] +
                                        mu[is, 5] * L[5] +
                                        mu[is, 6] * L[6] +
                                        mu[is, 7] * L[7] +
                                        mu[is, 8] * L[8])
            end
        end  #inbounds

        for is in 1:s
            Eval[is] = false
            for k in eachindex(uj)
                DY[is] = abs(U[is][k] - Uz[is][k])
                if DY[is] > 0.0
                    Eval[is] = true
                    if DY[is] < Dmin[is][k]
                        Dmin[is][k] = DY[is]
                        iter = true
                        #					elseif DY[is]>abs(U[is][k])*1e-8
                        #						iter=true
                    end
                else
                    D0 += 1
                end
            end

            if Eval[is] == true
                nfcn[1] += 1
                f(F[is], U[is], p, tj + hc[is])
                @. L[is] = hb[is] * F[is]
            end
        end

        if (iter == false && D0 < elems && plusIt)
            iter = true
            plusIt = false
        else
            plusIt = true
        end
    end  # while

    if (iter && nit == maxiters)
        println("Failure: maximum numbers of iterations=", maxiters, " at step=", j)
        return ("Failure", 0)
    end

    if (uiType <: CompiledFloats)

        #~Compensated summation
        indices = eachindex(uj)
        @inbounds begin
            for k in indices
                e0 = ej[k]
                for is in 1:s
                    e0 += muladd(F[is][k], hb[is], -L[is][k])
                end
                res = Base.TwicePrecision(uj[k], e0)
                for is in 1:s
                    res += L[is][k]
                end
                uj[k] = res.hi
                ej[k] = res.lo
            end
        end
        res = Base.TwicePrecision(tj, te) + dt
        ttj[1] = res.hi
        ttj[2] = res.lo
    else
        @. uj += L[1] + L[2] + L[3] + L[4] + L[5] + L[6] + L[7] + L[8]
        ttj[1] = tj + dt
    end

    dts[1] = min(dt, tf - (ttj[1] + ttj[2]))
    dts[2] = dt

    return ("Success", nit)
end

function IRKstep_fixed_Mix!(s,
    j,
    ttj,
    uj,
    ej,
    prob,
    dts,
    coeffs,
    cache,
    maxiters,
    initial_interp,
    abstol,
    reltol,
    adaptive,
    threading,
    mixed_precision,
    low_prec_type)
    @unpack mu, hc, hb, nu, alpha = coeffs
    @unpack f, u0, p, tspan, kwargs = prob

    @unpack U,
    Uz,
    L,
    Lz,
    F,
    Dmin,
    Eval,
    DY,
    rejects,
    nfcn,
    lambdas,
    Ulow,
    DU,
    DF,
    DL,
    delta,
    Fa,
    Fb,
    Plow,
    normU,
    lhb,
    lmu,
    nrmdigits = cache

    uiType = eltype(uj)
    realuiType = real(uiType)

    dt = dts[1]
    dtprev = dts[2]
    tf = tspan[2]

    elems = s * length(uj)

    tj = ttj[1]
    te = ttj[2]

    nit = 0

    if (dt != dtprev)
        HCoefficients!(mu, hc, hb, nu, dt, dtprev, realuiType)
        @unpack mu, hc, hb, nu, alpha = coeffs
        lhb .= hb
    end

    if initial_interp
        @inbounds begin
            for is in 1:s
                for k in eachindex(uj)
                    aux = zero(eltype(uj))
                    for js in 1:s
                        aux += nu[is, js] * L[js][k]
                    end
                    U[is][k] = (uj[k] + ej[k]) + aux
                end
            end
        end
    else
        @inbounds begin
            for is in 1:s
                @. U[is] = uj + ej
            end
        end
    end

    iter = true
    plusIt = true

    nit = 0
    @inbounds begin
        for is in 1:s
            Dmin[is] .= Inf
        end
    end

    @inbounds begin
        for is in 1:s
            nfcn[1] += 1
            f(F[is], U[is], p, tj + hc[is])
            @. L[is] = hb[is] * F[is]
        end
    end

    lmax = 1

    while (nit < maxiters && iter)
        nit += 1
        iter = false
        D0 = 0

        @inbounds begin
            for is in 1:s
                Uz[is] .= U[is]
                DiffEqBase.@.. U[is] = uj + (ej +
                                        mu[is, 1] * L[1] +
                                        mu[is, 2] * L[2] +
                                        mu[is, 3] * L[3] +
                                        mu[is, 4] * L[4] +
                                        mu[is, 5] * L[5] +
                                        mu[is, 6] * L[6] +
                                        mu[is, 7] * L[7] +
                                        mu[is, 8] * L[8])
                Ulow[is] .= U[is]
                normU[is] = copy(norm(Ulow[is]))
            end
        end # inbound

        for is in 1:s
            Eval[is] = false
            for k in eachindex(uj)
                DY[is] = abs(Rdigits(U[is][k], nrmdigits[]) -
                             Rdigits(Uz[is][k], nrmdigits[]))
                if DY[is] > 0.0
                    Eval[is] = true
                    if DY[is] < Dmin[is][k]
                        Dmin[is][k] = DY[is]
                        iter = true
                        #						elseif DY[is]>abs(U[is][k])*1e-8
                        #							iter=true
                    end
                else
                    D0 += 1
                    if abs(U[is][k] - Uz[is][k]) > 0.0
                        Eval[is] = true
                    end
                end
            end

            if Eval[is] == true
                nfcn[1] += 1
                f(F[is], U[is], p, tj + hc[is])
                @. delta[is] = muladd(F[is], hb[is], -L[is])
            else
                delta[is] .= 0
            end

            DL[is] .= delta[is]
        end

        lmax = min(lmax * 2, 6)

        for l in 1:lmax
            for is in 1:s
                if (Eval[is] == true)
                    DiffEqBase.@.. DU[is] = lmu[is, 1] * DL[1] +
                                            lmu[is, 2] * DL[2] +
                                            lmu[is, 3] * DL[3] +
                                            lmu[is, 4] * DL[4] +
                                            lmu[is, 5] * DL[5] +
                                            lmu[is, 6] * DL[6] +
                                            lmu[is, 7] * DL[7] +
                                            lmu[is, 8] * DL[8]
                end
            end

            for is in 1:s
                if (Eval[is] == true && norm(DU[is]) != 0)
                    beta = 1e-6 * norm(normU[is]) / norm(DU[is])
                    nfcn[2] += 2
                    tjci = convert(low_prec_type, tj + hc[is])
                    f(Fa[is], muladd.(beta, DU[is], Ulow[is]), Plow, tjci)
                    f(Fb[is], muladd.(-beta, DU[is], Ulow[is]), Plow, tjci)
                    @. DF[is] = 1 / (2 * beta) * (Fa[is] - Fb[is])
                    @. DL[is] = muladd(DF[is], lhb[is], delta[is])
                end
            end
        end # end  for l

        for is in 1:s
            if (Eval[is] == true)
                @. L[is] += DL[is]
            end
        end

        if (iter == false && D0 < elems && plusIt)
            iter = true
            plusIt = false
        else
            plusIt = true
        end
    end # while

    if (iter && nit == maxiters)
        println("Failure: maximum numbers of iterations=", maxiters, " at step=", j)
        return ("Failure", 0)
    end

    if (uiType <: CompiledFloats)

        #     ~ Compensated summation

        indices = eachindex(uj)
        @inbounds begin
            for k in indices
                e0 = ej[k]
                for is in 1:s
                    e0 += muladd(F[is][k], hb[is], -L[is][k])
                end
                res = Base.TwicePrecision(uj[k], e0)
                for is in 1:s
                    res += L[is][k]
                end
                uj[k] = res.hi
                ej[k] = res.lo
            end
        end

        res = Base.TwicePrecision(tj, te) + dt
        ttj[1] = res.hi
        ttj[2] = res.lo
    else
        @. uj += L[1] + L[2] + L[3] + L[4] + L[5] + L[6] + L[7] + L[8]
        ttj[1] = tj + dt
    end

    dts[1] = min(dt, tf - (ttj[1] + ttj[2]))
    dts[2] = dt

    return ("Success", nit)
end

#
# DynamicalODEFunction
#

function IRKstepDynODE_fixed!(s,
    j,
    ttj,
    uj,
    ej,
    prob,
    dts,
    coeffs,
    cache,
    maxiters,
    initial_interp,
    abstol,
    reltol,
    adaptive,
    threading)
    @unpack mu, hc, hb, nu, alpha = coeffs
    @unpack tspan, p = prob
    f1 = prob.f.f1
    f2 = prob.f.f2
    @unpack U, Uz, L, Lz, F, Dmin, Eval, DY, rejects, nfcn, lambdas, nrmdigits = cache

    uiType = eltype(uj)
    realuiType = real(uiType)

    dt = dts[1]
    dtprev = dts[2]
    tf = tspan[2]

    elems = s * length(uj)

    tj = ttj[1]
    te = ttj[2]

    nit = 0

    if (dt != dtprev)
        HCoefficients!(mu, hc, hb, nu, dt, dtprev, realuiType)
        @unpack mu, hc, hb, nu, alpha = coeffs
    end

    if initial_interp
        @inbounds begin
            for is in 1:s
                for k in eachindex(uj)
                    aux = zero(eltype(uj))
                    for js in 1:s
                        aux += nu[is, js] * L[js][k]
                    end
                    U[is][k] = (uj[k] + ej[k]) + aux
                end
            end
        end
    else
        @inbounds begin
            for is in 1:s
                @. U[is] = uj + ej
            end
        end
    end

    iter = true
    plusIt = true

    nit = 0
    for is in 1:s
        Dmin[is] .= Inf
    end

    @inbounds begin
        for is in 1:s
            nfcn[1] += 1
            f1(F[is].x[1], U[is].x[1], U[is].x[2], p, tj + hc[is])
            f2(F[is].x[2], U[is].x[1], U[is].x[2], p, tj + hc[is])
            @. L[is] = hb[is] * F[is]
        end
    end

    while (nit < maxiters && iter)
        nit += 1
        iter = false
        D0 = 0

        #           First part

        @inbounds begin
            for is in 1:s
                Uz[is].x[1] .= U[is].x[1]
                DiffEqBase.@.. U[is].x[1] = uj.x[1] + (ej.x[1] +
                                             mu[is, 1] * L[1].x[1] +
                                             mu[is, 2] * L[2].x[1] +
                                             mu[is, 3] * L[3].x[1] +
                                             mu[is, 4] * L[4].x[1] +
                                             mu[is, 5] * L[5].x[1] +
                                             mu[is, 6] * L[6].x[1] +
                                             mu[is, 7] * L[7].x[1] +
                                             mu[is, 8] * L[8].x[1])
            end
        end #inbounds

        for is in 1:s
            Eval[is] = false
            for k in eachindex(U[is].x[1])
                DY[is] = abs(U[is].x[1][k] - Uz[is].x[1][k])
                if DY[is] > 0.0
                    Eval[is] = true
                    if DY[is] < Dmin[is].x[1][k]
                        Dmin[is].x[1][k] = DY[is]
                        iter = true
                        #							elseif DY[is]>abs(U[is].x[1][k])*1e-8
                        #								iter=true
                    end
                else
                    D0 += 1
                end
            end

            if Eval[is] == true
                nfcn[1] += 1
                f2(F[is].x[2], U[is].x[1], U[is].x[2], p, tj + hc[is])
                @. L[is].x[2] = hb[is] * F[is].x[2]
            end
        end

        #           Second part

        for is in 1:s
            Uz[is].x[2] .= U[is].x[2]
            DiffEqBase.@.. U[is].x[2] = uj.x[2] + (ej.x[2] +
                                         mu[is, 1] * L[1].x[2] +
                                         mu[is, 2] * L[2].x[2] +
                                         mu[is, 3] * L[3].x[2] +
                                         mu[is, 4] * L[4].x[2] +
                                         mu[is, 5] * L[5].x[2] +
                                         mu[is, 6] * L[6].x[2] +
                                         mu[is, 7] * L[7].x[2] +
                                         mu[is, 8] * L[8].x[2])
        end

        for is in 1:s
            Eval[is] = false
            for k in eachindex(U[is].x[2])
                DY[is] = abs(U[is].x[2][k] - Uz[is].x[2][k])
                if DY[is] > 0.0
                    Eval[is] = true
                    if DY[is] < Dmin[is].x[2][k]
                        Dmin[is].x[2][k] = DY[is]
                        iter = true
                        #						  elseif DY[is]>abs(U[is].x[2][k])*1e-8
                        #							  iter=true
                    end
                else
                    D0 += 1
                end
            end

            if Eval[is] == true
                #						nfcn[1]+=1
                f1(F[is].x[1], U[is].x[1], U[is].x[2], p, tj + hc[is])
                @. L[is].x[1] = hb[is] * F[is].x[1]
            end
        end

        if (iter == false && D0 < elems && plusIt)
            iter = true
            plusIt = false
        else
            plusIt = true
        end
    end # while iter

    if (iter && nit == maxiters)
        println("Failure: maximum numbers of iterations=", maxiters, " at step=", j)
        return ("Failure", 0)
    end

    if (uiType <: CompiledFloats)

        #           ~Compensated summation

        indices = eachindex(uj)
        @inbounds begin
            for k in indices
                e0 = ej[k]
                for is in 1:s
                    e0 += muladd(F[is][k], hb[is], -L[is][k])
                end
                res = Base.TwicePrecision(uj[k], e0)
                for is in 1:s
                    res += L[is][k]
                end
                uj[k] = res.hi
                ej[k] = res.lo
            end
        end

        res = Base.TwicePrecision(tj, te) + dt
        ttj[1] = res.hi
        ttj[2] = res.lo

    else
        @. uj += L[1] + L[2] + L[3] + L[4] + L[5] + L[6] + L[7] + L[8]
        ttj[1] = tj + dt
    end

    dts[1] = min(dt, tf - (ttj[1] + ttj[2]))
    dts[2] = dt

    return ("Success", nit)
end
