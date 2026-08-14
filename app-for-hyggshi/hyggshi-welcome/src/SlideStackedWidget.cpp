#include "SlideStackedWidget.h"
#include <QPropertyAnimation>
#include <QParallelAnimationGroup>
#include <QEasingCurve>
#include <QGraphicsOpacityEffect>

SlideStackedWidget::SlideStackedWidget(QWidget *parent)
    : QStackedWidget(parent) {}

void SlideStackedWidget::slideToIndex(int index) {
  if (m_animating || index == currentIndex() || index < 0 || index >= count()) {
    return;
  }

  const bool forward = index > currentIndex();
  QWidget *current = currentWidget();
  QWidget *next = widget(index);
  if (!current || !next) return;

  const int w = width();
  const QPoint startPos(forward ? w : -w, 0);
  const QPoint endPosCurrent(forward ? -w : w, 0);

  next->setGeometry(0, 0, w, height());
  next->move(startPos);
  next->show();
  next->raise();

  // Fade nhẹ trên trang mới để chuyển động mềm hơn, không chỉ trượt cứng.
  auto *fx = new QGraphicsOpacityEffect(next);
  next->setGraphicsEffect(fx);
  auto *fadeAnim = new QPropertyAnimation(fx, "opacity", this);
  fadeAnim->setDuration(m_durationMs);
  fadeAnim->setStartValue(0.35);
  fadeAnim->setEndValue(1.0);
  fadeAnim->setEasingCurve(QEasingCurve::OutCubic);

  auto *slideNext = new QPropertyAnimation(next, "pos", this);
  slideNext->setDuration(m_durationMs);
  slideNext->setEasingCurve(QEasingCurve::OutCubic);
  slideNext->setStartValue(startPos);
  slideNext->setEndValue(QPoint(0, 0));

  auto *slideCurrent = new QPropertyAnimation(current, "pos", this);
  slideCurrent->setDuration(m_durationMs);
  slideCurrent->setEasingCurve(QEasingCurve::OutCubic);
  slideCurrent->setStartValue(QPoint(0, 0));
  slideCurrent->setEndValue(endPosCurrent);

  m_animating = true;
  auto *group = new QParallelAnimationGroup(this);
  group->addAnimation(fadeAnim);
  group->addAnimation(slideNext);
  group->addAnimation(slideCurrent);

  connect(group, &QParallelAnimationGroup::finished, this,
          [this, index, current, next]() {
            next->setGraphicsEffect(nullptr);
            setCurrentIndex(index);
            current->move(0, 0);
            m_animating = false;
            emit animationFinished();
          });
  group->start(QAbstractAnimation::DeleteWhenStopped);
}
