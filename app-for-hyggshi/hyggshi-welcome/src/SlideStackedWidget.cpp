#include "SlideStackedWidget.h"

#include <QParallelAnimationGroup>
#include <QPropertyAnimation>
#include <QEasingCurve>
#include <QGraphicsOpacityEffect>

SlideStackedWidget::SlideStackedWidget(QWidget *parent)
    : QStackedWidget(parent) {}

void SlideStackedWidget::slideToIndex(int index) {
  if (m_animating || index == currentIndex() || index < 0 || index >= count()) {
    return;
  }

  if (m_reducedMotion) {
    setCurrentIndex(index);
    emit animationFinished();
    return;
  }

  QWidget *current = currentWidget();
  QWidget *next = widget(index);
  if (!current || !next || width() <= 0 || height() <= 0) {
    setCurrentIndex(index);
    emit animationFinished();
    return;
  }

  const bool forward = index > currentIndex();
  const int w = width();
  const QPoint startPos(forward ? w : -w, 0);
  const QPoint endPosCurrent(forward ? -w : w, 0);

  next->setGeometry(rect());
  next->move(startPos);
  next->show();
  next->raise();

  auto *fx = new QGraphicsOpacityEffect(next);
  next->setGraphicsEffect(fx);

  auto *fadeAnim = new QPropertyAnimation(fx, "opacity");
  fadeAnim->setDuration(m_durationMs);
  fadeAnim->setStartValue(0.35);
  fadeAnim->setEndValue(1.0);
  fadeAnim->setEasingCurve(QEasingCurve::OutCubic);

  auto *slideNext = new QPropertyAnimation(next, "pos");
  slideNext->setDuration(m_durationMs);
  slideNext->setStartValue(startPos);
  slideNext->setEndValue(QPoint(0, 0));
  slideNext->setEasingCurve(QEasingCurve::OutCubic);

  auto *slideCurrent = new QPropertyAnimation(current, "pos");
  slideCurrent->setDuration(m_durationMs);
  slideCurrent->setStartValue(QPoint(0, 0));
  slideCurrent->setEndValue(endPosCurrent);
  slideCurrent->setEasingCurve(QEasingCurve::OutCubic);

  m_animating = true;

  auto *group = new QParallelAnimationGroup(this);
  group->addAnimation(fadeAnim);
  group->addAnimation(slideNext);
  group->addAnimation(slideCurrent);

  connect(group, &QParallelAnimationGroup::finished, this,
          [this, index, current, next]() {
            next->setGraphicsEffect(nullptr);
            current->move(0, 0);
            next->move(0, 0);
            setCurrentIndex(index);
            m_animating = false;
            emit animationFinished();
          });

  group->start(QAbstractAnimation::DeleteWhenStopped);
}
