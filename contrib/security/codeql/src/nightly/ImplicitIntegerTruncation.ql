/**
 * @name Implicit integer truncation
 * @description An integer value is implicitly narrowed to a shorter integer type
 *              without an explicit cast. This can cause silent data loss.
 *              Under -Werror=all, GCC 8.3 rejects these conversions even for
 *              small integer literals (e.g. uchar x[2] = {3,4}).
 * @kind problem
 * @problem.severity warning
 * @precision medium
 * @id firedancer-io/implicit-integer-truncation
 * @tags reliability
 *       correctness
 *       types
 */

import cpp
import filter

/**
 * Holds if expression `e` is implicitly converted from integral type `fromType`
 * to the narrower integral type `toType` without an explicit cast.
 *
 * Note: integer promotion artifacts are included (e.g. `uchar c = a + b` where
 * `a + b` has type `int` due to promotion). These may be numerous; add explicit
 * casts (e.g. `(uchar)(a + b)`) to suppress individual findings.
 */
predicate implicitIntegerTruncation(Expr e, IntegralType fromType, IntegralType toType) {
  not e.hasExplicitConversion() and
  not e.isInMacroExpansion() and
  fromType = e.getType().getUnderlyingType() and
  toType = e.getConversion().getType().getUnderlyingType() and
  not fromType instanceof BoolType and
  not toType instanceof BoolType and
  toType.getSize() < fromType.getSize()
}

from Expr e, IntegralType fromType, IntegralType toType
where
  implicitIntegerTruncation(e, fromType, toType) and
  included(e.getLocation())
select e,
  "Implicit truncation from " + fromType.getName() + " to " + toType.getName() + "."
