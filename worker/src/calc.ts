/**
 * 金利計算ロジック
 * - 元利均等返済 / 元金均等返済の月額・総額計算
 * - 市場平均との乖離診断
 * - 金利上昇シミュレーション
 */

// ── 返済計算 ──────────────────────────────────

export interface LoanCondition {
  principal: number;       // 借入元本（円）
  annualRate: number;      // 年利（%）例: 1.5
  termYears: number;       // 返済期間（年）
}

export interface RepaymentResult {
  method: 'equal_payment' | 'equal_principal';
  monthlyFirst: number;    // 初月の返済額
  monthlyLast: number;     // 最終月の返済額（元金均等は毎月変動）
  totalPayment: number;    // 総返済額
  totalInterest: number;   // 利息総額
  annualPayment: number;   // 年間返済額（初年ベース概算）
}

/**
 * 元利均等返済
 * PMT = P × r × (1+r)^n / ((1+r)^n - 1)
 */
export function calcEqualPayment(cond: LoanCondition): RepaymentResult {
  const P = cond.principal;
  const r = cond.annualRate / 100 / 12; // 月利
  const n = cond.termYears * 12;        // 返済回数

  if (r === 0) {
    const monthly = Math.round(P / n);
    return {
      method: 'equal_payment',
      monthlyFirst: monthly,
      monthlyLast: monthly,
      totalPayment: P,
      totalInterest: 0,
      annualPayment: monthly * 12,
    };
  }

  const rn = Math.pow(1 + r, n);
  const monthly = Math.round(P * r * rn / (rn - 1));
  const totalPayment = monthly * n;
  const totalInterest = totalPayment - P;

  return {
    method: 'equal_payment',
    monthlyFirst: monthly,
    monthlyLast: monthly,
    totalPayment,
    totalInterest,
    annualPayment: monthly * 12,
  };
}

/**
 * 元金均等返済
 * 毎月の元金 = P / n（固定）
 * 毎月の利息 = 残元金 × r（逓減）
 */
export function calcEqualPrincipal(cond: LoanCondition): RepaymentResult {
  const P = cond.principal;
  const r = cond.annualRate / 100 / 12;
  const n = cond.termYears * 12;

  const monthlyPrincipal = P / n;
  let totalInterest = 0;
  let firstPayment = 0;
  let lastPayment = 0;

  for (let i = 0; i < n; i++) {
    const remaining = P - monthlyPrincipal * i;
    const interest = remaining * r;
    totalInterest += interest;

    const payment = Math.round(monthlyPrincipal + interest);
    if (i === 0) firstPayment = payment;
    if (i === n - 1) lastPayment = payment;
  }

  totalInterest = Math.round(totalInterest);

  return {
    method: 'equal_principal',
    monthlyFirst: firstPayment,
    monthlyLast: lastPayment,
    totalPayment: P + totalInterest,
    totalInterest,
    annualPayment: firstPayment * 12, // 初年ベース概算
  };
}

// ── 乖離診断 ──────────────────────────────────

export interface DeviationResult {
  userRate: number;
  marketRate: number;
  deviation: number;          // ユーザー金利 - 市場平均（正なら高い）
  deviationBps: number;       // bp（ベーシスポイント）単位
  verdict: 'high' | 'average' | 'low';
  annualDifference: number;   // 年間の利息差額（円）
  comment: string;
}

export function diagnoseDeviation(
  userRate: number,
  marketRate: number,
  principal: number,
  termYears: number,
): DeviationResult {
  const deviation = Math.round((userRate - marketRate) * 1000) / 1000;
  const deviationBps = Math.round(deviation * 100);

  // 年間利息差概算（残高×金利差）
  const annualDifference = Math.round(principal * Math.abs(deviation) / 100);

  let verdict: 'high' | 'average' | 'low';
  let comment: string;

  if (deviationBps > 30) {
    verdict = 'high';
    comment = `お借入金利は市場平均より ${deviation.toFixed(3)}%（${deviationBps}bp）高い水準です。年間約${annualDifference.toLocaleString()}円の差額が生じている可能性があります。金融機関への相談を検討されてもよいかもしれません。`;
  } else if (deviationBps >= -30) {
    verdict = 'average';
    comment = `お借入金利は市場平均と概ね同水準です。`;
  } else {
    verdict = 'low';
    comment = `お借入金利は市場平均より低い水準にあります。現在の条件は良好といえる可能性があります。`;
  }

  return { userRate, marketRate, deviation, deviationBps, verdict, annualDifference, comment };
}

// ── 金利上昇シミュレーション ────────────────────────

export interface SimulationScenario {
  rateIncrease: number;       // 上昇幅（%）
  newRate: number;
  equalPayment: RepaymentResult;
  equalPrincipal: RepaymentResult;
  monthlyIncrease: number;    // 元利均等の月額増加額
  annualIncrease: number;     // 元利均等の年間増加額
}

export function simulateRateIncrease(
  baseCond: LoanCondition,
  increases: number[] = [0.25, 0.5, 1.0],
): SimulationScenario[] {
  const baseEP = calcEqualPayment(baseCond);

  return increases.map((inc) => {
    const newCond: LoanCondition = {
      ...baseCond,
      annualRate: baseCond.annualRate + inc,
    };
    const ep = calcEqualPayment(newCond);
    const eprin = calcEqualPrincipal(newCond);

    return {
      rateIncrease: inc,
      newRate: Math.round((baseCond.annualRate + inc) * 1000) / 1000,
      equalPayment: ep,
      equalPrincipal: eprin,
      monthlyIncrease: ep.monthlyFirst - baseEP.monthlyFirst,
      annualIncrease: ep.annualPayment - baseEP.annualPayment,
    };
  });
}
