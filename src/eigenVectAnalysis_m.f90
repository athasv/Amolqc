module eigenVectAnalysis_m
    use kinds_m, only: r8, i4
    use parsing_m, only: getinta, getloga
    use global_m
    use fPsi2_m
    use atom_m
    use mpiInterface_m, only: myMPIReduceSumInteger
    use rWSample_m, only: rWSample, getSampleSize, getFirst, isNext, getNext, getWalker
    use psiMax_m, only: psimax
    use randomWalker_m, only: RandomWalker, pos, resetTo
    use singularityParticles_m, only: singularity_particles

    implicit none

    private
    public :: eigenVectAnalysis

contains
    subroutine eigenVectAnalysis(smpl, psimax_obj)
        type(RWSample), intent(inout) :: smpl
        type(psimax), intent(inout)   :: psimax_obj
        type(RandomWalker), pointer   :: rw
        integer                       :: n, i, lwork, info, yml, k
        real(r8)                      :: xx(3*getNElec()), sample(3*getNElec())
        real(r8)                      :: x(getNElec()), y(getNElec()), z(getNElec())
        real(r8)                      :: H(SIZE(xx),SIZE(xx))
        real(r8)                      :: lambda(SIZE(xx)), work2(3*SIZE(xx)-1)

        !initialize variables
        rw => getFirst(smpl)
        n = getNElec()

        !create output document
        open(newunit=yml, file = 'eigenvect_analysis.yml')
        write(yml, '(a)') '---'
        write(yml, '(a)') 'Structures:'

        !eigenvector analysis
        do
            !get sample
            call pos(rw, x, y, z)
            do i = 1, n
                xx(3*i-2) = x(i)
                xx(3*i-1) = y(i)
                xx(3*i)   = z(i)
            end do
            sample = xx

            !correct for singularities
            call psimax_obj%correctForSingularities(sample, H)

            !get eigenvalues and -vectors
            lwork = 3*SIZE(sample)-1
            call DSYEV('V', 'U', SIZE(sample), H, SIZE(sample), lambda, work2, lwork, info)
            call assert(info == 0, 'eigenVectAnalysis: Inversion failed!')

            !write eigenvalues to document
            write(yml, '(a)', ADVANCE = 'no') '  - Eigenvalues: ['
            do i = 1, SIZE(lambda)
                write(yml, '(es14.6)', ADVANCE = 'no') lambda(i)
                if (i /= SIZE(lambda)) write(yml, '(a)', ADVANCE = 'no') ','
            end do
            write(yml, '(a)')']'

            !write eigenvectors to document
            write(yml, '(a)') '    Eigenvectors: ['
            do i = 1, SIZE(lambda)
                do k = 1, SIZE(lambda)/3
                    write(yml,'(a, es14.6, a)', ADVANCE = 'no') '      [', H(3*k-2, i), ','
                    write(yml,'(es14.6, a)', ADVANCE = 'no') H(3*k-1, i), ','
                    write(yml,'(es14.6, a)') H(3*k, i), '],'
                    end do
                end do
            write(yml, '(a)')'      ]'

            !get next sample
            if (.not. isNext(smpl)) exit
            rw => getNext(smpl)
        end do

        !close document
        write(yml, '(a)') '...'
        close(yml)

    end subroutine eigenVectAnalysis

end module eigenVectAnalysis_m